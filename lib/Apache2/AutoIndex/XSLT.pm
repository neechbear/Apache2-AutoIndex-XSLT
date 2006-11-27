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
no strict qw(subs); # This is for ./DistBuild.PL only - can be commented out
use File::Spec qw();
use Fcntl qw(:mode);
use Apache2::RequestRec qw();
use Apache2::Access qw();
use Apache2::Log qw();
use Apache2::URI qw();
use Apache2::Const -compile => qw(:common :options DIR_MAGIC_TYPE);

use vars qw($VERSION);
$VERSION = '0.01' || sprintf('%d.%02d', q$Revision: 531 $ =~ /(\d+)/g);


# Let's deal with this another time shall we?
#if (mod_perl2->module('Apache::Status')){
#	Apache::Status->menu_item('AutoIndex' => sprintf('%s status',__PACKAGE__), \&_status);
#}


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
		$r->content_type('text/xml');
		return Apache2::Const::OK if $r->header_only;
		return _dir_xml($r);

	# Otherwise he's not the messiah, he's a very naughty boy
	} else {
		$r->log_reason(
				sprintf('%s Directory index forbidden by rule', __PACKAGE__),
				sprintf('%s (%s)', $r->uri, $r->filename),
			);
		return Apache2::Const::FORBIDDEN;
	}
}


sub _dir_xml {
	my $r = shift;

	my $dh;
	unless (opendir($dh,$r->filename)) {
		$r->log_reason(
				sprintf("%s Unable to open directory handle for '%s': %s",
					__PACKAGE__, $r->filename, $!),
				sprintf('%s (%s)', $r->uri, $r->filename),
			);
		return Apache2::Const::FORBIDDEN;
	}

	my $xslt = -f File::Spec->catfile($r->document_root,'index.xslt')
			? 'index.xslt' : '';
	_print_xml_header($xslt);
	printf "<index path=\"%s\" href=\"%s\" >\n", $r->uri, $r->construct_url;

	while (my $id = readdir($dh)) {
		next if $id eq '.';
		next if $id eq '..' && $r->uri =~ m,^/?$,;

		my $filename = File::Spec->catfile($r->filename,$id);
		my $type = _file_type ($id,$filename);
		my $attr = _stat_file($filename);

		($attr->{ext}) = $id =~ /\.([a-z0-9_]+)$/i;
		if ($type eq 'file') {
			$attr->{icon} = -f File::Spec->catfile($r->document_root,'icons',lc("$attr->{ext}.gif")) ?
					'/icons/'.lc("$attr->{ext}.gif") : '/icons/__unknown.gif';
		}

		$attr->{title} = $id;
		$attr->{desc} = '';

		my $element = sprintf('<%s id="%s" %s />', $type, $id,
				join(' ',map { sprintf('%s="%s"',$_,$attr->{$_}) }
					keys(%{$attr})),
			);

		print "\t$element\n";
	}

	print "</index>\n";
	closedir($dh);
	return Apache2::Const::OK;
}


sub _file_type {
	my ($id,$filename) = @_;
	return -d $filename && $id eq '..' ? 'updir' :
#		$id =~ /^(My[ -_]?(Computer|Documents|Pictures|Videos|Music)|
#		Network[ -_]?Neighborhood|Logitech[ -_]?Webcam|Control[ -_]?Panel)
#		$/xi ? 'special' :
#			-l $filename ? 'link' :
			-d $filename ? 'dir' :
			'file';
}


sub _stat_file {
	my %stat;
	@stat{qw(dev ino mode nlink uid gid rdev size
			atime mtime ctime blksize blocks)} = lstat($_[0]);

	my %rtn;
	$rtn{$_} = $stat{$_} for qw(uid gid mtime ctime size);
	$rtn{perms} = _file_mode($stat{mode});
	$rtn{owner} = scalar getpwuid($rtn{uid});
	$rtn{group} = scalar getgrgid($rtn{gid});

	return \%rtn;
}


sub _file_mode {
	my $mode = shift;
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


sub _print_xml_header {
	my $xslt = shift;

	my @dtd = (
			'<!DOCTYPE svn [',
			'  <!ELEMENT svn   (index)>',
			'  <!ATTLIST svn   version CDATA #REQUIRED',
			'                  href    CDATA #REQUIRED>',
			'  <!ELEMENT index (updir?, (file | dir)*)>',
			'  <!ATTLIST index name    CDATA #IMPLIED',
			'                  path    CDATA #IMPLIED',
			'                  rev     CDATA #IMPLIED>',
			'  <!ELEMENT updir EMPTY>',
			'  <!ELEMENT file  EMPTY>',
			'  <!ATTLIST file  name    CDATA #REQUIRED',
			'                  href    CDATA #REQUIRED>',
			'  <!ELEMENT dir   EMPTY>',
			'',
			'  <!ATTLIST dir   name    CDATA #REQUIRED',
			'                  href    CDATA #REQUIRED>',
			']>',
		);
	@dtd = ();

	print qq{<?xml version="1.0"?>\n};
	print qq{<?xml-stylesheet type="text/xsl" href="$xslt"?>} if $xslt;
	print "$_\n" for @dtd;
}


sub _status {
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


1;

=pod

=head1 NAME

Apache2::AutoIndex::XSLT - XSLT Based Directory Listings

=head1 SYNOPSIS

 <Location />
     SetHandler perl-script
     PerlResponseHandler Apache2::AutoIndex::XSLT
     Options +Indexes
 </Location>

=head1 DESCRIPTION

This module is designed as a drop in mod_perl2 replacement for the mod_dir and
mod_index modules. It uses user configurable XSLT stylesheets to generate the
directory listings.

THIS IS A DEVELOPMENT RELEASE.

=head1 SEE ALSO

L<Apache::AutoIndex>

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


