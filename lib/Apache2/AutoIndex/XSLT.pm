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
use Fcntl qw(:mode);
use URI::Escape qw(); # Try to replace with Apache2::Util or Apache2::URI

use Apache2::Access qw();
use Apache2::CmdParms qw();
use Apache2::Const -compile => qw(:common :options :config DIR_MAGIC_TYPE);
use Apache2::Directive qw();
use Apache2::Log qw();
use Apache2::Module qw();
use Apache2::ServerRec qw();
use Apache2::RequestRec qw();
use Apache2::SubRequest qw();
use Apache2::ServerUtil qw();
use Apache2::URI qw();
use Apache2::Util qw();

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
eval {
	Apache2::Status->menu_item('AutoIndex' => sprintf('%s status',__PACKAGE__),
		\&status) if Apache2::Module::loaded('Apache2::Status');
};





#
# Apache response handler
#

sub handler {
	my $r = shift;

      my %secs = ();
  
      $r->content_type('text/plain');
  
      my $s = $r->server;
      my $dir_cfg = get_config($s, $r->per_dir_config);
      my $srv_cfg = get_config($s);
  
      if ($s->is_virtual) {
          $secs{"1: Main Server"}  = get_config(Apache2::ServerUtil->server);
          $secs{"2: Virtual Host"} = $srv_cfg;
          $secs{"3: Location"}     = $dir_cfg;
      }
      else {
          $secs{"1: Main Server"}  = $srv_cfg;
          $secs{"2: Location"}     = $dir_cfg;
       }
  
      $r->printf("Processing by %s.\n", 
          $s->is_virtual ? "virtual host" : "main server");
  
      for my $sec (sort keys %secs) {
          $r->print("\nSection $sec\n");
          for my $k (sort keys %{ $secs{$sec}||{} }) {
              my $v = exists $secs{$sec}->{$k}
                  ? $secs{$sec}->{$k}
                  : 'UNSET';
              $v = '[' . (join ", ", map {qq{"$_"}} @$v) . ']'
                  if ref($v) eq 'ARRAY';
              $r->printf("%-10s : %s\n", $k, $v);
          }
      }
  
      return Apache2::Const::OK;

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
		eval { $rtn = dir_xml($r); };
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

	eval {
		require Data::Dumper;
		my $srv_cfg = get_config(Apache2::ServerUtil->server);
		my $vrt_cfg = get_config($r->server);
		my $dir_cfg = get_config($r->server, $r->per_dir_config);
		push @status, sprintf('<b>srv_cfg:</b> <pre>%s</pre>', Data::Dumper::Dumper($srv_cfg));
		push @status, sprintf('<b>vrt_cfg:</b> <pre>%s</pre>', Data::Dumper::Dumper($vrt_cfg));
		push @status, sprintf('<b>dir_cfg:</b> <pre>%s</pre>', Data::Dumper::Dumper($dir_cfg));
	};
	push @status, $@;

	return \@status;
}










#
# Private helper subroutines
#

sub dir_xml {
	my $r = shift;

	# Increment listings counter
	$COUNTERS{Listings}++;

	# Get query string values
	my $qstring = {};
	for (split(/[&;]/,($r->args||''))) {
		my ($k,$v) = split('=',$_,2);
		next unless defined $k;
		$v = '' unless defined $v;
		$qstring->{URI::Escape::uri_unescape($k)} =
			URI::Escape::uri_unescape($v);
	}

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

		require Data::Dumper;
		my $srv_cfg = get_config(Apache2::ServerUtil->server);
		my $vrt_cfg = get_config($r->server);
		my $dir_cfg = get_config($r->server, $r->per_dir_config);
		printf('<b>srv_cfg:</b> <pre>%s</pre>', Data::Dumper::Dumper($srv_cfg));
		printf('<b>vrt_cfg:</b> <pre>%s</pre>', Data::Dumper::Dumper($vrt_cfg));
		printf('<b>dir_cfg:</b> <pre>%s</pre>', Data::Dumper::Dumper($dir_cfg));

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
					map { sprintf('%s="%s"',$_,$attr->{$_})
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
		printf($format,$option,$qstring->{$option});
	}

	# Apache configuration directives
	for my $directive (@DIRECTIVES) {
		printf($format,$directive,'');
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
			'  <!ATTLIST index href    CDATA #REQUIRED',
			'                  path    CDATA #REQUIRED>',
			'  <!ELEMENT options (option*)>',
			'  <!ATTLIST options name  CDATA #REQUIRED',
			'                    value CDATA #IMPLIED>',
			'  <!ELEMENT updir EMPTY>',
			'  <!ATTLIST updir icon    CDATA #IMPLIED>',
			'  <!ELEMENT file  EMPTY>',
			'  <!ATTLIST file  href    CDATA #REQUIRED',
			'                  title   CDATA #REQUIRED',
			'                  desc    CDATA #IMPLIED',
			'                  owner   CDATA #IMPLIED',
			'                  group   CDATA #IMPLIED',
			'                  uid     CDATA #REQUIRED',
			'                  gid     CDATA #REQUIRED',
			'                  ctime   CDATA #REQUIRED',
			'                  mtime   CDATA #REQUIRED',
			'                  perms   CDATA #REQUIRED',
			'                  size    CDATA #REQUIRED',
			'                  icon    CDATA #IMPLIED',
			'                  ext     CDATA #IMPLIED>',
			'  <!ELEMENT dir   EMPTY>',
			'  <!ATTLIST dir   href    CDATA #REQUIRED',
			'                  title   CDATA #REQUIRED',
			'                  desc    CDATA #IMPLIED',
			'                  owner   CDATA #IMPLIED',
			'                  group   CDATA #IMPLIED',
			'                  uid     CDATA #REQUIRED',
			'                  gid     CDATA #REQUIRED',
			'                  ctime   CDATA #REQUIRED',
			'                  mtime   CDATA #REQUIRED',
			'                  perms   CDATA #REQUIRED',
			'                  size    CDATA #REQUIRED',
			'                  icon    CDATA #IMPLIED>',
			']>',
		);
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

	# Reformat times to this format: yyyy-mm-ddThh:mm-tz:tz
	for (qw(mtime ctime)) {
		$rtn{$_} = Apache2::Util::ht_time(
				$r->pool, $rtn{$_},
				'%Y-%m-%dT%H:%M-00:00',
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
	return (S_ISREG($mode)  ? '-' :
			S_ISDIR($mode)  ? 'd' :
			S_ISLNK($mode)  ? 'l' :
			S_ISBLK($mode)  ? 'b' :
			S_ISCHR($mode)  ? 'c' :
			S_ISFIFO($mode) ? 'p' :
			S_ISSOCK($mode) ? 's' : '?' ) .

			( ($mode & S_IRUSR) ? 'r' : '-' ) .
			( ($mode & S_IWUSR) ? 'w' : '-' ) .
			( ($mode & S_ISUID) ? (($mode & S_IXUSR) ? 's' : 'S')
								: (($mode & S_IXUSR) ? 'x' : '-') ) .

			( ($mode & S_IRGRP) ? 'r' : '-' ) .
			( ($mode & S_IWGRP) ? 'w' : '-' ) .
			( ($mode & S_ISGID) ? (($mode & S_IXGRP) ? 's' : 'S')
								: (($mode & S_IXGRP) ? 'x' : '-') ) .

			( ($mode & S_IROTH) ? 'r' : '-' ) .
			( ($mode & S_IWOTH) ? 'w' : '-' ) .
			( ($mode & S_ISVTX) ? (($mode & S_IXOTH) ? 't' : 'T')
								: (($mode & S_IXOTH) ? 'x' : '-') );
}










#
# Handle all Apache configuration directives
#

sub get_config {
	Apache2::Module::get_config(__PACKAGE__, @_);
}

eval {
	Apache2::Module::add(__PACKAGE__, [ map { { name => $_ } } @DIRECTIVES ]);
};
if ($@) {
	warn $@;
	print $@;
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


