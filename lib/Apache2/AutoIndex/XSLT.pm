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
use Apache2::RequestRec qw();
use Apache2::SubRequest qw();
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

use vars qw($VERSION @DIRECTIVES);
$VERSION = '0.00' || sprintf('%d.%02d', q$Revision: 531 $ =~ /(\d+)/g);
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

		# The _dir_xml subroutine will actually print and output
		# all the XML DTD and XML, returning an OK if everything
		# was successful.
		my $rtn = Apache2::Const::SERVER_ERROR;
		eval { $rtn = _dir_xml($r); };
#		print $@ if $@;
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
	eval {
		require Data::Dumper;
		my $cfg = Apache::ModuleConfig->get($r);
		push @status, sprintf('<pre>%s</pre>', Dumper($cfg));
	};

	return \@status;
}










#
# Private helper subroutines
#

sub _dir_xml {
	my $r = shift;

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
	_print_xml_header($r,$xslt);
	printf "<index path=\"%s\" href=\"%s\" >\n", $r->uri, $r->construct_url;
	_print_xml_options($r,$qstring);
	print "\t<updir icon=\"/icons/__back.gif\" />\n" unless $r->uri =~ m,^/?$,;

	# Build a list of attributes for each item in the directory and then
	# print it as an element in the index tree.
	while (my $id = readdir($dh)) {
		next if $id =~ /^\./;
		my $subr = $r->lookup_file($id); # Not used yet
		my $filename = File::Spec->catfile($directory,$id);
		my $type = _file_type($r,$id,$filename);
		my $attr = _build_attributes($r,$id,$filename,$type);
		printf("\t<%s %s />\n", $type, join(' ',
					map { sprintf('%s="%s"',$_,$attr->{$_})
							if defined $_ && defined $attr->{$_} }
						keys(%{$attr})
				));
	}

	# Close the index tree, directory handle and return
	print "</index>\n";
	closedir($dh);
	return Apache2::Const::OK;
}


sub _print_xml_options {
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


sub _build_attributes {
	my ($r,$id,$filename,$type) = @_;
	return {} if $type eq 'updir';

	my $attr = _stat_file($r,$filename);

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


sub _file_type {
	my ($r,$id,$file) = @_;
	return -d $file && $id eq '..' ? 'updir' : -d $file ? 'dir' : 'file';
}


sub _print_xml_header {
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


sub _stat_file {
	my ($r,$filename) = @_;

	my %stat;
	@stat{qw(dev ino mode nlink uid gid rdev size
			atime mtime ctime blksize blocks)} = lstat($filename);

	my %rtn;
	$rtn{$_} = $stat{$_} for qw(uid gid mtime ctime size);
	$rtn{perms} = _file_mode($stat{mode});
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


sub _file_mode {
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

sub SERVER_CREATE {}
sub DIR_CREATE {}
sub SERVER_MERGE {}
sub DIR_MERGE {}

sub AddAlt {}
sub AddAltByEncoding {}
sub AddAltByType {}
sub AddDescription {}
sub AddIcon {}
sub AddIconByEncoding {}
sub AddIconByType {}
sub DefaultIcon {}
sub HeaderName {}
sub IndexIgnore {}
sub IndexOptions {}
sub IndexOrderDefault {}
sub IndexStyleSheet {}
sub ReadmeName {}
sub DirectoryIndex {}
sub DirectorySlash {}

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


