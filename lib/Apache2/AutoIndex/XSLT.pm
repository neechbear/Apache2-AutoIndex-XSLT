############################################################
#
#   $Id$
#   Apache2::AutoIndex::XSLT - XSLT Based Directory Listings
#
#   Copyright 2006 Nicola Worthington
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
############################################################

package Apache2::AutoIndex::XSLT;
# vim:ts=4:sw=4:tw=78

use 5.6.1;
use strict;
use warnings;
#use warnings FATAL => 'all';

use File::Spec qw();
use Fcntl qw();
use URI::Escape qw(); # Try to replace with Apache2::Util or Apache2::URI

# This is libapreq2 - we're parsing the query string manually
# to avoid loading another non-standard module
# use Apache2::Request qw(); 

# These two are required in general
use Apache2::ServerRec qw();
use Apache2::RequestRec qw();

# Used to return various Apache constant response codes
use Apache2::Const -compile => qw(:common :options :config DIR_MAGIC_TYPE);

# Used for writing to Apache logs
use Apache2::Log qw();

# Used for parsing Apache configuration directives
use Apache2::Module qw();
use Apache2::CmdParms qw(); # Needed for use with Apache2::Module callbacks

# Used to get the main server Apache2::ServerRec (not the virtual ServerRec)
use Apache2::ServerUtil qw();

# Used for Apache2::Util::ht_time time formatting
use Apache2::Util qw();

use Apache2::URI qw(); # Needed for $r->construct_url

#use Apache2::Access qw();     # Possibly not needed
#use Apache2::Directive qw();  # Possibly not needed
#use Apache2::SubRequest qw(); # Possibly not needed

# Start here ...
# http://perl.apache.org/docs/2.0/user/config/custom.html
# http://perl.apache.org/docs/2.0/api/Apache2/Module.html
# http://perl.apache.org/docs/2.0/api/Apache2/Const.html
# http://perl.apache.org/docs/2.0/user/porting/compat.html
# http://httpd.apache.org/docs/2.2/mod/mod_autoindex.html
# http://httpd.apache.org/docs/2.2/mod/mod_dir.html
# http://www.modperl.com/book/chapters/ch8.html

use vars qw($VERSION @DIRECTIVES %COUNTERS);
$VERSION = '0.00' || sprintf('%d.%02d', q$Revision: 531 $ =~ /(\d+)/g);
%COUNTERS = (Listings => 0, Files => 0, Directories => 0, Errors => 0);
@DIRECTIVES = qw(AddAlt AddAltByEncoding AddAltByType AddDescription AddIcon
	AddIconByEncoding AddIconByType DefaultIcon HeaderName IndexIgnore
	IndexOptions IndexOrderDefault IndexStyleSheet ReadmeName DirectoryIndex
	DirectorySlash);

# Let Apache2::Status know we're here if it's hanging around
eval { Apache2::Status->menu_item('AutoIndex' => sprintf('%s status',__PACKAGE__),
	\&status) if Apache2::Module::loaded('Apache2::Status'); };

# Register our interesting in a bunch of Apache configuration directives
eval { Apache2::Module::add(__PACKAGE__, [ map { { name => $_ } } @DIRECTIVES ]); };
if ($@) { warn $@; print $@; }





#
# Apache response handler
#

sub handler {
	my $r = shift;

	# Get query string values - use this manual code instead of
	# Apache2::Request because it uses less memory, and Apache2::Request
	# does not come as standard with mod_perl2 (it's libapreq2 on CPAN)
	my $qstring = {};
	for (split(/[&;]/,($r->args||''))) {
		my ($k,$v) = split('=',$_,2);
		next unless defined $k;
		$v = '' unless defined $v;
		$qstring->{URI::Escape::uri_unescape($k)} =
			URI::Escape::uri_unescape($v);
	}

	# Dump the configuration out to screen
	if (defined $qstring->{CONFIG}) {
		$r->content_type('text/plain');
		print dump_apache_configuration($r);
		return Apache2::Const::OK;
	}

	# Only handle directories
	return Apache2::Const::DECLINED unless $r->content_type &&
			$r->content_type eq Apache2::Const::DIR_MAGIC_TYPE;

	# Make sure we're at a URL with a trailing slash
	unless ($r->uri =~ m,/$,) {# || $r->path_info){
		$r->headers_out->add(Location => sprintf('%s/%s',
				$r->uri,
				($r->args ? '?'.$r->args : '')
			));
		return Apache2::Const::REDIRECT;
	}

	# Return a directory listing if we're allowed to
	if ($r->allow_options & Apache2::Const::OPT_INDEXES) {
		$r->content_type('text/xml; charset="utf-8"');
		return Apache2::Const::OK if $r->header_only;

		# The dir_xml subroutine will actually print and output
		# all the XML DTD and XML, returning an OK if everything
		# was successful.
		my $rtn = Apache2::Const::SERVER_ERROR;
		eval { $rtn = dir_xml($r,$qstring); };
		if ($@) {
			$COUNTERS{Errors}++;
			warn $@, print $@;
		};
		return $rtn;

	# Otherwise he's not the messiah, he's a very naughty boy
	} else {
		$r->log_reason(
				sprintf('%s Directory index forbidden by rule', __PACKAGE__),
				sprintf('%s (%s)', $r->uri, $r->filename),
			);
		return Apache2::Const::FORBIDDEN;
	}
}










#
# Apache2::Status status page handler
#

sub status {
	my $r = shift;

	my @status;
	push @status, sprintf('<b>%s %s</b><br />', __PACKAGE__, $VERSION);
	push @status, sprintf('<p><b>Configuration Directives:</b> %s</p>',
			join(', ',@DIRECTIVES)
		);

	push @status, "<table>\n";
	while (my ($k,$v) = each %COUNTERS) {
		push @status, "<tr><th align=\"left\">$k:</th><td>$v</td></tr>\n";
	}
	push @status, "</table>\n";

	push @status, "<p><b>Configuration:</b><br />\n";
	push @status, dump_apache_configuration($r)."</p>\n";

	return \@status;
}










#
# Private helper subroutines
#

sub dir_xml {
	my ($r,$qstring) = @_;

	# Increment listings counter
	$COUNTERS{Listings}++;

	# Get directory to work on
	my $directory = $r->filename;
	$r->filename("$directory/") unless $directory =~ m/\/$/;

	# Open the physical directory on disk to get a list of all items inside.
	# This won't pick up virtual directories aliased in Apache's configs.
	my $dh;
	unless (opendir($dh,$directory)) {
		$r->log_reason(
				sprintf("%s Unable to open directory handle for '%s': %s",
					__PACKAGE__, $directory, $!),
				sprintf('%s (%s)', $r->uri, $directory),
			);
		return Apache2::Const::FORBIDDEN;
	}

	# Send the XML header and top of the index tree
	my $xslt = '/index.xslt';
	print_xml_header($r,$xslt);
	printf "<index path=\"%s\" href=\"%s\" >\n", $r->uri, $r->construct_url;
	print_xml_options($r,$qstring);
	print "\t<updir icon=\"/icons/__back.gif\" />\n" unless $r->uri =~ m,^/?$,;

	# Build a list of attributes for each item in the directory and then
	# print it as an element in the index tree.
	while (my $id = readdir($dh)) {
		next if $id =~ /^\./;
		#my $subr = $r->lookup_file($id); # Not used yet

		my $filename = File::Spec->catfile($directory,$id);
		my $type = file_type($r,$id,$filename);
		my $attr = build_attributes($r,$id,$filename,$type);

		printf("\t<%s %s />\n", $type, join(' ',
					map { sprintf("\n\t\t%s=\"%s\"",$_,$attr->{$_})
							if defined $_ && defined $attr->{$_} }
						keys(%{$attr})
				));

		$COUNTERS{Files}++ if $type eq 'file';
		$COUNTERS{Directories}++ if $type eq 'dir';
	}

	# Close the index tree, directory handle and return
	print "</index>\n";
	closedir($dh);
	return Apache2::Const::OK;
}


sub print_xml_options {
	my ($r,$qstring) = @_;

	my $format = "\t\t<option name=\"%s\" value=\"%s\" />\n";
	print "\t<options>\n";

	# Query string options
	for my $option (qw(C O F V P)) {
		printf($format,$option,$qstring->{$option})
			if defined $qstring->{$option} &&
				$qstring->{$option} =~ /\S+/;
	}

	# Apache configuration directives
	my $cfg = get_config($r->server, $r->per_dir_config);
	for my $d (@DIRECTIVES) {
		for my $value ((
			!exists($cfg->{$d}) ? ()
								: ref($cfg->{$d}) eq 'ARRAY'
								? $cfg->{$d}
								: ($cfg->{$d})
				)) {
			printf($format,$d,$value);
		}
	}

	print "\t</options>\n";
}


sub build_attributes {
	my ($r,$id,$filename,$type) = @_;
	return {} if $type eq 'updir';

	my $attr = stat_file($r,$filename);

	if ($type eq 'file') {
		($attr->{ext}) = $id =~ /\.([a-z0-9_]+)$/i;
		$attr->{icon} = '/icons/__unknown.gif';
		$attr->{icon} = $attr->{ext} &&
			-f File::Spec->catfile($r->document_root,'icons',lc("$attr->{ext}.gif"))
				? '/icons/'.lc("$attr->{ext}.gif")
				: '/icons/__unknown.gif';
	}

	$attr->{icon} = '/icons/__dir.gif' if $type eq 'dir';
	$attr->{icon} = '/icons/__back.gif' if $type eq 'updir';

	unless ($type eq 'updir') {
		#$attr->{id} = $id; # This serves no real purpose anymor
		$attr->{href} = URI::Escape::uri_escape($id);
		$attr->{href} .= '/' if $type eq 'dir';
		$attr->{title} = $id;
		#$attr->{desc} = '';
	}

	return $attr;
}


sub file_type {
	my ($r,$id,$file) = @_;
	return -d $file && $id eq '..' ? 'updir' : -d $file ? 'dir' : 'file';
}


sub print_xml_header {
	my ($r,$xslt) = @_;

	print qq{<?xml version="1.0"?>\n};
	print qq{<?xml-stylesheet type="text/xsl" href="$xslt"?>\n} if $xslt;
	print qq{$_\n} for (
			'<!DOCTYPE index [',
			'  <!ELEMENT index (options?, updir?, (file | dir)*)>',
			'  <!ATTLIST index href      CDATA #REQUIRED',
			'                  path      CDATA #REQUIRED>',
			'  <!ELEMENT options (option*)>',
			'  <!ELEMENT option EMPTY>',
			'  <!ATTLIST option name     CDATA #REQUIRED',
			'                   value    CDATA #IMPLIED>',
			'  <!ELEMENT updir EMPTY>',
			'  <!ATTLIST updir icon      CDATA #IMPLIED>',
			'  <!ELEMENT file  EMPTY>',
			'  <!ATTLIST file  href      CDATA #REQUIRED',
			'                  title     CDATA #REQUIRED',
			'                  desc      CDATA #IMPLIED',
			'                  owner     CDATA #IMPLIED',
			'                  group     CDATA #IMPLIED',
			'                  uid       CDATA #REQUIRED',
			'                  gid       CDATA #REQUIRED',
			'                  ctime     CDATA #REQUIRED',
			'                  nicectime CDATA #IMPLIED',
			'                  mtime     CDATA #REQUIRED',
			'                  nicemtime CDATA #IMPLIED',
			'                  perms     CDATA #REQUIRED',
			'                  size      CDATA #REQUIRED',
			'                  nicesize  CDATA #IMPLIED',
			'                  icon      CDATA #IMPLIED',
			'                  ext       CDATA #IMPLIED>',
			'  <!ELEMENT dir   EMPTY>',
			'  <!ATTLIST dir   href      CDATA #REQUIRED',
			'                  title     CDATA #REQUIRED',
			'                  desc      CDATA #IMPLIED',
			'                  owner     CDATA #IMPLIED',
			'                  group     CDATA #IMPLIED',
			'                  uid       CDATA #REQUIRED',
			'                  gid       CDATA #REQUIRED',
			'                  ctime     CDATA #REQUIRED',
			'                  nicectime CDATA #IMPLIED',
			'                  mtime     CDATA #REQUIRED',
			'                  nicemtime CDATA #IMPLIED',
			'                  perms     CDATA #REQUIRED',
			'                  size      CDATA #REQUIRED',
			'                  nicesize  CDATA #IMPLIED',
			'                  icon      CDATA #IMPLIED>',
			']>',
		);
}


sub comify {
	local $_ = shift;
	s/^\s+|\s+$//g;
	1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
	return $_;
}


sub stat_file {
	my ($r,$filename) = @_;

	my %stat;
	@stat{qw(dev ino mode nlink uid gid rdev size
			atime mtime ctime blksize blocks)} = lstat($filename);

	my %rtn;
	$rtn{$_} = $stat{$_} for qw(uid gid mtime ctime size);
	$rtn{perms} = file_mode($stat{mode});
	$rtn{owner} = scalar getpwuid($rtn{uid});
	$rtn{group} = scalar getgrgid($rtn{gid});

	$rtn{nicesize} = comify(sprintf('%d KB',
						($rtn{size} + ($rtn{size} ? 1024 : 0))/1024
					));
#	eval {
#		require Number::Format;
#		my $format = new Number::Format;
#		$rtn{nicesize} = $format->format_bytes($rtn{size},0).'B';
#		$rtn{nicesize} =~ s/(\D+)$/ $1/;
#	};

	# Reformat times to this format: yyyy-mm-ddThh:mm-tz:tz
	for (qw(mtime ctime)) {
		my $time = $rtn{$_};
		$rtn{$_} = Apache2::Util::ht_time(
				$r->pool, $time,
				'%Y-%m-%dT%H:%M-00:00',
				0,
			);
		$rtn{"nice$_"} = Apache2::Util::ht_time(
				$r->pool, $time,
				'%d/%m/%Y %H:%M',
				0,
			);
	}

	return \%rtn;
}


sub file_mode {
	my $mode = shift;

	# This block of code is taken with thanks from
	# http://zarb.org/~gc/resource/find_recent,
	# written by Guillaume Cottenceau.
	return (
		Fcntl::S_ISREG($mode)  ? '-' :
		Fcntl::S_ISDIR($mode)  ? 'd' :
		Fcntl::S_ISLNK($mode)  ? 'l' :
		Fcntl::S_ISBLK($mode)  ? 'b' :
		Fcntl::S_ISCHR($mode)  ? 'c' :
		Fcntl::S_ISFIFO($mode) ? 'p' :
		Fcntl::S_ISSOCK($mode) ? 's' : '?' ) .

		( ($mode & Fcntl::S_IRUSR()) ? 'r' : '-' ) .
		( ($mode & Fcntl::S_IWUSR()) ? 'w' : '-' ) .
		( ($mode & Fcntl::S_ISUID()) ? (($mode & Fcntl::S_IXUSR()) ? 's' : 'S')
									: (($mode & Fcntl::S_IXUSR()) ? 'x' : '-') ) .

		( ($mode & Fcntl::S_IRGRP()) ? 'r' : '-' ) .
		( ($mode & Fcntl::S_IWGRP()) ? 'w' : '-' ) .
		( ($mode & Fcntl::S_ISGID()) ? (($mode & Fcntl::S_IXGRP()) ? 's' : 'S')
									: (($mode & Fcntl::S_IXGRP()) ? 'x' : '-') ) .

		( ($mode & Fcntl::S_IROTH()) ? 'r' : '-' ) .
		( ($mode & Fcntl::S_IWOTH()) ? 'w' : '-' ) .
		( ($mode & Fcntl::S_ISVTX()) ? (($mode & Fcntl::S_IXOTH()) ? 't' : 'T')
									: (($mode & Fcntl::S_IXOTH()) ? 'x' : '-') );
}










#
# Handle all Apache configuration directives
#

sub dump_apache_configuration {
	my $r = shift;

	my $rtn = '';
	my %secs = ();
	my $s = $r->server;
	my $dir_cfg = get_config($s, $r->per_dir_config);
	my $srv_cfg = get_config($s);
  
	if ($s->is_virtual) {
		$secs{"1: Main Server"}  = get_config(Apache2::ServerUtil->server);
		$secs{"2: Virtual Host"} = $srv_cfg;
		$secs{"3: Location"}     = $dir_cfg;
	} else {
		$secs{"1: Main Server"}  = $srv_cfg;
		$secs{"2: Location"}     = $dir_cfg;
	}
  
	$rtn .= sprintf("Processing by %s.\n", 
	$s->is_virtual ? "virtual host" : "main server");
  
	for my $sec (sort keys %secs) {
		$rtn .= "\nSection $sec\n";
		for my $k (sort keys %{ $secs{$sec}||{} }) {
			my $v = exists $secs{$sec}->{$k}
					? $secs{$sec}->{$k}
					: 'UNSET';
			$v = '[' . (join ", ", map {qq{"$_"}} @$v) . ']'
				if ref($v) eq 'ARRAY';
			$rtn .= sprintf("%-10s : %s\n", $k, $v);
		}
	}

	return $rtn;
}
 
sub get_config {
	Apache2::Module::get_config(__PACKAGE__, @_);
}

sub AddAlt            { push_val('AddAlt',            @_) }
sub AddAltByEncoding  { push_val('AddAltByEncoding',  @_) }
sub AddAltByType      { push_val('AddAltByType',      @_) }
sub AddDescription    { push_val('AddDescription',    @_) }
sub AddIcon           { push_val('AddIcon',           @_) }
sub AddIconByEncoding { push_val('AddIconByEncoding', @_) }
sub AddIconByType     { push_val('AddIconByType',     @_) }
sub IndexIgnore       { push_val('IndexIgnore',       @_) }
sub IndexOptions      { push_val('IndexOptions',      @_) }
sub DefaultIcon       { set_val('DefaultIcon',        @_) }
sub HeaderName        { set_val('HeaderName',         @_) }
sub IndexOrderDefault { set_val('IndexOrderDefault',  @_) }
sub IndexStyleSheet   { set_val('IndexStyleSheet',    @_) }
sub ReadmeName        { set_val('ReadmeName',         @_) }
sub DirectoryIndex    { set_val('DirectoryIndex',     @_) }
sub DirectorySlash    { set_val('DirectorySlash',     @_) }

sub DIR_CREATE { defaults(@_) }
sub SERVER_CREATE { defaults(@_) }
sub SERVER_MERGE { merge(@_); }
sub DIR_MERGE { merge(@_); }

sub set_val {
	my ($key, $self, $parms, $arg) = @_;
	$self->{$key} = $arg;
	unless ($parms->path) {
		my $srv_cfg = Apache2::Module::get_config($self,
		$parms->server);
		$srv_cfg->{$key} = $arg;
	}
}
  
sub push_val {
	my ($key, $self, $parms, $arg) = @_;
	push @{ $self->{$key} }, $arg;
	unless ($parms->path) {
		my $srv_cfg = Apache2::Module::get_config($self,$parms->server);
		push @{ $srv_cfg->{$key} }, $arg;
	}
}

sub defaults {
	my ($class, $parms) = @_;
	return bless {
			HeaderName => 'HEADER',
			ReadmeName => 'FOOTER',
			DirectoryIndex => 'index.html',
			DefaultIcon => '/icons/__unknown.gif',
		}, $class;
}

sub merge {
	my ($base, $add) = @_;
	my %mrg = ();
	for my $key (keys %$base, keys %$add) {
		next if exists $mrg{$key};
		if ($key eq 'MyPlus') {
			$mrg{$key} = ($base->{$key}||0) + ($add->{$key}||0);
		} elsif ($key eq 'MyList') {
			push @{ $mrg{$key} },
			@{ $base->{$key}||[] }, @{ $add->{$key}||[] };
		} elsif ($key eq 'MyAppend') {
			$mrg{$key} = join " ", grep defined, $base->{$key},
			$add->{$key};
		} else {
			# override mode
			$mrg{$key} = $base->{$key} if exists $base->{$key};
			$mrg{$key} = $add->{$key}  if exists $add->{$key};
		}
	}
	return bless \%mrg, ref($base);
}
  
1;






=pod

=head1 NAME

Apache2::AutoIndex::XSLT - XSLT Based Directory Listings

=head1 SYNOPSIS

 <Location />
     SetHandler perl-script
     PerlLoadModule Apache2::AutoIndex::XSLT
     PerlResponseHandler Apache2::AutoIndex::XSLT
     Options +Indexes
 </Location>

=head1 DESCRIPTION

This module is designed as a drop in mod_perl2 replacement for the mod_dir and
mod_index modules. It uses user configurable XSLT stylesheets to generate the
directory listings.

THIS IS A DEVELOPMENT RELEASE!

=head1 CONFIGURATION

=head2 AddAlt

=head2 AddAltByEncoding

=head2 AddAltByType

=head2 AddIcon

=head2 AddIconByEncoding

=head2 AddIconByType

=head2 DefaultIcon

=head2 DirectorySlash

=head2 IndexStyleSheet

=head2 AddDescription

=head2 DirectoryIndex

=head2 FancyIndexing

=head2 HeaderName

=head2 IndexIgnore

=head2 IndexOptions

=head2 IndexOrderDefault

=head2 ReadmeName

=head1 SEE ALSO

L<Apache::AutoIndex>,
L<http://httpd.apache.org/docs/2.2/mod/mod_autoindex.html>,
L<http://httpd.apache.org/docs/2.2/mod/mod_dir.html>

=head1 VERSION

$Id$

=head1 AUTHOR

Nicola Worthington <nicolaw@cpan.org>

L<http://perlgirl.org.uk>

If you like this software, why not show your appreciation by sending the
author something nice from her
L<Amazon wishlist|http://www.amazon.co.uk/gp/registry/1VZXC59ESWYK0?sort=priority>? 
( http://www.amazon.co.uk/gp/registry/1VZXC59ESWYK0?sort=priority )

With special thanks to Jennifer Beattie for developing the example XSLT
stylesheets.

=head1 COPYRIGHT

Copyright 2006 Nicola Worthington.

This software is licensed under The Apache Software License, Version 2.0.

L<http://www.apache.org/licenses/LICENSE-2.0>

=cut

__END__


