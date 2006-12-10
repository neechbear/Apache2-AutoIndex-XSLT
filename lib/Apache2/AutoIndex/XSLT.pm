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
use XML::Quote qw();
use URI::Escape qw(); # Try to replace with Apache2::Util or Apache2::URI

# This is libapreq2 - we're parsing the query string manually
# to avoid loading another non-standard module
# use Apache2::Request qw(); 

# These two are required in general
use Apache2::ServerRec qw(); # $r->server
use Apache2::RequestRec qw();
use Apache2::RequestUtil qw(); # $r->document_root

# Used to return various Apache constant response codes
use Apache2::Const -compile => qw(
		:common :options :config :cmd_how :override :types
	);

# Used for writing to Apache logs
use Apache2::Log qw();

# Used for parsing Apache configuration directives
use Apache2::Module qw();
use Apache2::CmdParms qw(); # Needed for use with Apache2::Module callbacks

# Used to get the main server Apache2::ServerRec (not the virtual ServerRec)
use Apache2::ServerUtil qw();

# Used for Apache2::Util::ht_time time formatting
use Apache2::Util qw();

use Apache2::URI qw(); # $r->construct_url
use Apache2::Access qw(); # $r->allow_options

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

use vars qw($VERSION %DIRECTIVES %COUNTERS %FILETYPES);
$VERSION = '0.00' || sprintf('%d.%02d', q$Revision: 531 $ =~ /(\d+)/g);
%COUNTERS = (Listings => 0, Files => 0, Directories => 0, Errors => 0);







#
# Apache response handler
#

sub handler {
	my $r = shift;

	# Only handle directories
	return Apache2::Const::DECLINED unless $r->content_type &&
			$r->content_type eq Apache2::Const::DIR_MAGIC_TYPE;

	# Parse query string and get config
	my ($qstring,$dir_cfg) = init_handler($r);

	# Read in the filetypes information
	if (!defined %FILETYPES && defined $dir_cfg->{FileTypesFilename}) {
		FileTypesFilename: for my $FileTypesFilename ($dir_cfg->{FileTypesFilename},
				File::Spec->catfile($r->document_root,$dir_cfg->{FileTypesFilename}),
				File::Spec->catfile(Apache2::ServerUtil->server_root,$dir_cfg->{FileTypesFilename})) {
			my $ext = '';
			if (open(FH,'<',$FileTypesFilename)) {
				while (local $_ = <FH>) {
					if (my ($k,$v) = $_ =~ /^\s*(\S+)\s*:\s*(\S.*?)\s*$/) {
						if ($k =~ /ext(ension)?/i) {
							$v =~ s/^\.//;
							$ext = $v || '';
						} elsif ($v) {
							$FILETYPES{lc($ext)}->{$k} = $v;
						}
					}
				}
				close(FH);
				last FileTypesFilename;
			}
		}
	}

	# Dump the configuration out to screen
	if (defined $qstring->{CONFIG}) {
		$r->content_type('text/plain');
		print dump_apache_configuration($r);
		return Apache2::Const::OK;
	}

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
		eval { $rtn = dir_xml($r,$dir_cfg,$qstring); };
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


sub transhandler {
	my $r = shift;

	# Only handle directories
	return Apache2::Const::DECLINED unless $r->uri =~ /\/$/;
	return Apache2::Const::DECLINED unless $r->content_type &&
			$r->content_type eq Apache2::Const::DIR_MAGIC_TYPE;

	# Parse query string and get config
	my ($qstring,$dir_cfg) = init_handler($r);

	foreach (@{$dir_cfg->{DirectoryIndex}}){
		my $subr = $r->lookup_uri($r->uri . $_);
		last if $subr->path_info;
		if (stat $subr->finfo){
			$r->uri($subr->uri);
			last;
		}
	}
	return Apache2::Const::DECLINED;
}








#
# Apache2::Status status page handler
#

# Let Apache2::Status know we're here if it's hanging around
eval { Apache2::Status->menu_item('AutoIndex' => sprintf('%s status',__PACKAGE__),
	\&status) if Apache2::Module::loaded('Apache2::Status'); };

sub status {
	my $r = shift;

	my @status;
	push @status, sprintf('<b>%s %s</b><br />', __PACKAGE__, $VERSION);
	push @status, sprintf('<p><b>Configuration Directives:</b> %s</p>',
			join(', ',keys %DIRECTIVES)
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

sub init_handler {
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

	# Get the configuration directives
	my $dir_cfg = get_config($r->server, $r->per_dir_config);

	return ($qstring,$dir_cfg);
}

sub dir_xml {
	my ($r,$dir_cfg,$qstring) = @_;

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
	print_xml_header($r,$dir_cfg);
	printf "<index path=\"%s\" href=\"%s\" >\n", $r->uri, $r->construct_url;
	print_xml_options($r,$qstring,$dir_cfg);
	print "\t<updir icon=\"/icons/__back.png\" />\n" unless $r->uri =~ m,^/?$,;

	# Build a list of attributes for each item in the directory and then
	# print it as an element in the index tree.
	while (my $id = readdir($dh)) {
		next if $id eq '..' || $id eq '.';
		next if grep($id =~ /^$_$/, @{$dir_cfg->{IndexIgnoreRegex}});
		#my $subr = $r->lookup_file($id); # Not used yet

		my $filename = File::Spec->catfile($directory,$id);
		my $type = file_type($r,$id,$filename);
		my $attr = build_attributes($r,$dir_cfg,$id,$filename,$type);

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
	my ($r,$qstring,$dir_cfg) = @_;

	my $format = "\t\t<option name=\"%s\" value=\"%s\" />\n";
	print "\t<options>\n";

	# Query string options
	for my $option (qw(C O F V P)) {
		printf($format,$option,$qstring->{$option})
			if defined $qstring->{$option} &&
				$qstring->{$option} =~ /\S+/;
	}

	# Apache configuration directives
	for my $d (keys %DIRECTIVES) {
		for my $value ((
			!exists($dir_cfg->{$d}) ? ()
								: ref($dir_cfg->{$d}) eq 'ARRAY'
								? @{$dir_cfg->{$d}}
								: ($dir_cfg->{$d})
				)) {
			printf($format,$d,$value);
		}
	}

	print "\t</options>\n";
}


sub build_attributes {
	my ($r,$dir_cfg,$id,$filename,$type) = @_;
	return {} if $type eq 'updir';

	my $attr = stat_file($r,$filename);

	if ($type eq 'file') {
		($attr->{ext}) = $id =~ /\.([a-z0-9_]+)$/i;
		$attr->{icon} = $dir_cfg->{DefaultIcon} || '';
		$attr->{icon} = $attr->{ext} &&
			-f File::Spec->catfile($r->document_root,'icons',lc("$attr->{ext}.png"))
				? '/icons/'.lc("$attr->{ext}.png")
				: $dir_cfg->{DefaultIcon} || '';
	}

	$attr->{icon} = '/icons/__dir.png' if $type eq 'dir';
	$attr->{icon} = '/icons/__back.png' if $type eq 'updir';

	unless ($type eq 'updir') {
		#$attr->{id} = $id; # This serves no real purpose anymor
		$attr->{href} = URI::Escape::uri_escape($id);
		$attr->{href} .= '/' if $type eq 'dir';
		$attr->{title} = XML::Quote::xml_quote($id);
		$attr->{desc} = $type eq 'dir' ? 'File Folder' : 'File';
		if ($attr->{ext}) {
			$attr->{desc} = exists $FILETYPES{lc($attr->{ext})} ?
					$FILETYPES{lc($attr->{ext})}->{DisplayName} || '' : '';
			$attr->{desc} ||= sprintf('%s File',uc($attr->{ext}));
			$attr->{desc} = XML::Quote::xml_quote($attr->{desc});
		}
	}

	return $attr;
}


sub file_type {
	my ($r,$id,$file) = @_;
	return -d $file && $id eq '..' ? 'updir' : -d $file ? 'dir' : 'file';
}


sub print_xml_header {
	my ($r,$dir_cfg) = @_;

	my $css  = $dir_cfg->{IndexStyleSheet} || '';
	my $xslt = $dir_cfg->{IndexXSLT} || '';

	print qq{<?xml version="1.0"?>\n};
	print qq{<?xml-stylesheet type="text/css" href="$css"?>\n} if $css;
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


sub glob2regex {
	my $glob = shift || '';
	$glob =~ s/\./\\./g; # . is a dot
	$glob =~ s/\?/./g;   # ? is any single character
	$glob =~ s/\*/.*/g;  # * means any number of any characters
	$glob =~ s/(?<!\\)([\(\)\[\]\+])/\\$1/g; # Escape metacharacters
	return $glob;        # Now a regex
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
# http://perl.apache.org/docs/2.0/user/config/custom.html
#

#@DIRECTIVES = qw(AddAlt AddAltByEncoding AddAltByType AddDescription AddIcon
#	AddIconByEncoding AddIconByType DefaultIcon HeaderName IndexIgnore
#	IndexOptions IndexOrderDefault IndexStyleSheet ReadmeName DirectoryIndex
#	DirectorySlash IndexXSLT FileTypesFilename);

%DIRECTIVES = (
	# http://search.cpan.org/~nicolaw/Apache2-AutoIndex-XSLT/lib/Apache2/AutoIndex/XSLT.pm
		IndexXSLT  => {
				name         => 'IndexXSLT',
				req_override => Apache2::Const::OR_ALL,
				args_how     => Apache2::Const::TAKE1,
				errmsg       => 'IndexXSLT url-path',
			},
		FileTypesFilename => {
				name         => 'FileTypesFilename',
				req_override => Apache2::Const::OR_ALL,
				args_how     => Apache2::Const::TAKE1,
				errmsg       => 'FileTypesFilename file',
			},

	# http://httpd.apache.org/docs/2.2/mod/mod_autoindex.html
		AddAlt => {
				name         => 'AddAlt',
				req_override => Apache2::Const::OR_ALL,
				args_how     => Apache2::Const::ITERATE2,
				errmsg       => 'AddAlt string file [file] ...',
			},
		AddAltByEncoding => {
				name         => 'AddAltByEncoding',
				req_override => Apache2::Const::OR_ALL,
				args_how     => Apache2::Const::ITERATE2,
				errmsg       => 'AddAltByEncoding string MIME-encoding [MIME-encoding] ...',
			},
		AddAltByType       => Apache2::Const::ITERATE2,
		AddIcon            => Apache2::Const::ITERATE2,
		AddIconByEncoding  => Apache2::Const::ITERATE2,
		AddIconByType      => Apache2::Const::ITERATE2,
		DefaultIcon        => Apache2::Const::TAKE1,
		HeaderName         => Apache2::Const::TAKE1,
		IndexIgnore        => Apache2::Const::ITERATE,
		IndexOptions       => Apache2::Const::ITERATE,
		IndexOrderDefault  => Apache2::Const::TAKE2,
		IndexStyleSheet    => Apache2::Const::TAKE1,
		ReadmeName         => Apache2::Const::TAKE1,

	# http://httpd.apache.org/docs/2.2/mod/mod_dir.html
		DirectoryIndex     => Apache2::Const::ITERATE,
		DirectorySlash     => Apache2::Const::FLAG,
	);

# Register our interest in a bunch of Apache configuration directives
eval {
	Apache2::Module::add(__PACKAGE__, [
		map {
			if (ref($DIRECTIVES{$_}) eq 'HASH') {
				$DIRECTIVES{$_}
			} else {
				{
				name         => $_,
		#		func         => sprintf('%s::%s',__PACKAGE__, $_),
				req_override => Apache2::Const::OR_ALL,
				args_how     => Apache2::Const::ITERATE,
		#		errmsg       => 'MyParameter Entry1 [Entry2 ... [EntryN]]',
				}
			}
		} keys %DIRECTIVES
	]);
}; if ($@) { warn $@; print $@; }

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

	require Data::Dumper;
	local $Data::Dumper::Terse = 1;
	local $Data::Dumper::Deepcopy = 1;
	local $Data::Dumper::Sortkeys = 1;
	$rtn = Data::Dumper::Dumper(\%secs);
  
#	for my $sec (sort keys %secs) {
#		$rtn .= "\nSection $sec\n";
#		for my $k (sort keys %{ $secs{$sec}||{} }) {
#			my $v = exists $secs{$sec}->{$k}
#					? $secs{$sec}->{$k}
#					: 'UNSET';
#			$v = '[' . (join ", ", map {qq{"$_"}} @$v) . ']'
#				if ref($v) eq 'ARRAY';
#			$rtn .= sprintf("%-10s : %s\n", $k, $v);
#		}
#	}

	return $rtn;
}
 
sub get_config {
	Apache2::Module::get_config(__PACKAGE__, @_);
}

sub AddAlt {
	push_val( 'AddAlt', $_[0], $_[1], join(' ',$_[2],$_[3]) );
	push_val( 'AddAltRegex', $_[0], $_[1], 
			[( $_[2],glob2regex($_[3]) )],
		);
}

sub AddAltByEncoding  { push_val('AddAltByEncoding',  @_) }
sub AddAltByType      { push_val('AddAltByType',      @_) }
sub AddDescription    { push_val('AddDescription',    @_) }

sub AddIcon           {
	push_val( 'AddIcon', $_[0], $_[1], join(' ',$_[2],$_[3]) );
	my $icon = $_[2];
	my $alt = '';
	if ($icon =~ /^\s*\(?(\S+?),(\S+?)\)\s*$/) {
		$alt = $1;
		$icon = $2;
	}
	push_val( 'AddIconRegex', $_[0], $_[1], 
			[( $alt,$icon,glob2regex($_[3]) )],
		);
}

sub AddIconByEncoding { push_val('AddIconByEncoding', @_) }
sub AddIconByType     { push_val('AddIconByType',     @_) }

sub IndexIgnore       {
	push_val( 'IndexIgnore', @_ );
	push_val( 'IndexIgnoreRegex', $_[0], $_[1], glob2regex($_[2]) );
}

sub IndexOptions      { push_val('IndexOptions',      @_) }
sub DirectoryIndex    { push_val('DirectoryIndex',    @_) }
sub DefaultIcon       { set_val('DefaultIcon',        @_) }
sub HeaderName        { set_val('HeaderName',         @_) }
sub IndexOrderDefault { set_val('IndexOrderDefault',  @_) }
sub IndexStyleSheet   { set_val('IndexStyleSheet',    @_) }
sub IndexXSLT         { set_val('IndexXSLT',          @_) }
sub ReadmeName        { set_val('ReadmeName',         @_) }
sub DirectorySlash    { set_val('DirectorySlash',     @_) }
sub FileTypesFilename { set_val('FileTypesFilename',  @_) }

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
	my ($key, $self, $parms, @args) = @_;
	push @{ $self->{$key} }, @args;
	unless ($parms->path) {
		my $srv_cfg = Apache2::Module::get_config($self,$parms->server);
		push @{ $srv_cfg->{$key} }, @args;
	}
}

sub defaults {
	my ($class, $parms) = @_;
	return bless {
			HeaderName => 'HEADER',
			ReadmeName => 'FOOTER',
			DirectoryIndex => [qw(index.html index.shtml)],
			IndexXSLT => '/index.xslt',
			DefaultIcon => '/icons/__unknown.png',
			IndexIgnore => [()],
			FileTypesFilename => File::Spec->catfile(Apache2::ServerUtil->server_root,'filetypes.dat'),
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

 PerlLoadModule Apache2::AutoIndex::XSLT
 <Location>
     SetHandler perl-script
     PerlResponseHandler Apache2::AutoIndex::XSLT
     Options +Indexes
     IndexXSLT /index.xslt
     DefaultIcon /icons/__unknown.png
     IndexIgnore .*
     IndexIgnore index.xslt
     IndexIgnore robots.txt
     IndexIgnore sitemap.gz
 </Location>

=head1 DESCRIPTION

This module is designed as a drop in mod_perl2 replacement for the mod_dir and
mod_index modules. It uses user configurable XSLT stylesheets to generate the
directory listings.

THIS CODE IS INCOMPLETE -- THIS IS A DEVELOPMENT RELEASE!

=head1 CONFIGURATION

This module attempts to emulate as much as the functionality from the Apache
mod_dir and mod_index modules as possible. Some of this is performed directly
by the Apache::AutoIndex::XSLT module itself, and some through a combination
of the I<options> elements presented in the output XML and the XSLT stylesheet.
As a result, some of these configuration directives will do little or nothing
at all if the XSLT stylesheet used does not use them.

=head2 AddAlt

     AddAlt "PDF file" *.pdf
     AddAlt Compressed *.gz *.zip *.Z

I<AddAlt> provides the alternate text to display for a file, instead of an
icon. File is a file extension, partial filename,
wild-card expression or full filename for files to describe. If String
contains any whitespace, you have to enclose it in quotes (" or '). This
alternate text is displayed if the client is image-incapable, has image
loading disabled, or fails to retrieve the icon.

=head2 AddAltByEncoding

     AddAltByEncoding gzip x-gzip

I<AddAltByEncoding> provides the alternate text to display for a file, instead
of an icon. MIME-encoding is a valid content-encoding,
such as x-compress. If String contains any whitespace, you have to enclose it
in quotes (" or '). This alternate text is displayed if the client is
image-incapable, has image loading disabled, or fails to retrieve the icon.

=head2 AddAltByType

     AddAltByType 'plain text' text/plain

I<AddAltByType> sets the alternate text to display for a file, instead of an
icon. MIME-type is a valid content-type, such as
text/html. If String contains any whitespace, you have to enclose it in quotes
(" or '). This alternate text is displayed if the client is image-incapable,
has image loading disabled, or fails to retrieve the icon.

=head2 AddDescription

     AddDescription "The planet Mars" /web/pics/mars.png

This sets the description to display for a file. File is
a file extension, partial filename, wild-card expression or full filename for
files to describe. String is enclosed in double quotes (").

=head2 AddIcon

     AddIcon (IMG,/icons/image.xbm) .gif .jpg .xbm
     AddIcon /icons/dir.xbm ^^DIRECTORY^^
     AddIcon /icons/backup.xbm *~

This sets the icon to display next to a file ending in name. Icon is either a
(%-escaped) relative URL to the icon, or of
the format  (alttext,url) where alttext  is the text tag given for an icon for
non-graphical browsers.

Name is either ^^DIRECTORY^^ for directories, ^^BLANKICON^^ for blank lines
(to format the list correctly), a file extension, a wildcard expression, a
partial filename or a complete filename.

I<AddIconByType> should be used in preference to I<AddIcon>, when possible.

=head2 AddIconByEncoding

     AddIconByEncoding /icons/compress.xbm x-compress

This sets the icon to display next to files. Icon is
either a (%-escaped) relative URL to the icon, or of the format (alttext,url)
where alttext is the text tag given for an icon for non-graphical browsers.

MIME-encoding is a wildcard expression matching required the content-encoding.

=head2 AddIconByType

     AddIconByType (IMG,/icons/image.xbm) image/*

This sets the icon to display next to files of type MIME-type.
Icon is either a (%-escaped) relative URL to the icon, or of
the format (alttext,url)  where alttext is the text tag given for an icon for
non-graphical browsers.

MIME-type is a wildcard expression matching required the mime types.

=head2 DefaultIcon

     DefaultIcon /icons/__unknown.png

The I<DefaultIcon> directive sets the icon to display for files when no
specific icon is known. Url-path is a (%-escaped)
relative URL to the icon.

=head2 HeaderName

=head2 IndexIgnore

     IndexIgnore README .htindex *.bak *~

The I<IndexIgnore> directive adds to the list of files to hide when listing a
directory. File is a shell-style wildcard expression or full filename. Multiple
I<IndexIgnore> directives add to the list, rather than the replacing the list
of ignored files. By default, the list contains . (the current directory).

=head2 IndexOptions

     IndexOptions +DescriptionWidth=* +FancyIndexing +FoldersFirst +HTMLTable
     IndexOptions +IconsAreLinks +IconHeight=16 +IconWidth=16 +IgnoreCase
     IndexOptions +IgnoreClient +NameWidth=* +ScanHTMLTitles +ShowForbidden
     IndexOptions +SuppressColumnSorting +SuppressDescription
     IndexOptions +SuppressHTMLPreamble +SuppressIcon +SuppressLastModified
     IndexOptions +SuppressRules +SuppressSize +TrackModified +VersionSort
     IndexOptions +XHTML

The I<IndexOptions> directive specifies the behavior of the directory indexing.

See L<http://httpd.apache.org/docs/2.2/mod/mod_autoindex.html#indexoptions>.

=head2 IndexOrderDefault

     IndexOrderDefault Ascending Name

The I<IndexOrderDefault> directive is used in combination with the
I<FancyIndexing> index option. By default, fancyindexed directory listings are
displayed in ascending order by filename; the I<IndexOrderDefault> allows you
to change this initial display order.

I<IndexOrderDefault> takes two arguments. The first must be either Ascending or
Descending, indicating the direction of the sort. The second argument must be
one of the keywords Name, Date, Size, or Description, and identifies the
primary key. The secondary key is always the ascending filename.

You can force a directory listing to only be displayed in a particular order by
combining this directive with the I<SuppressColumnSorting> index option; this
will prevent the client from requesting the directory listing in a different
order.

=head2 IndexStyleSheet

     IndexStyleSheet "/css/style.css" 

The I<IndexStyleSheet> directive sets the name of the file that will be used as
the CSS for the index listing. 

=head2 ReadmeName

     ReadmeName FOOTER.html

The I<ReadmeName> directive sets the name of the file that will be appended to
the end of the index listing. Filename is the name of the file to include, and
is taken to be relative to the location being indexed. If Filename begins with
a slash, it will be taken to be relative to the I<DocumentRoot>.

=head2 DirectoryIndex

     DirectoryIndex index.html index.shtml

The I<DirectoryIndex> directive sets the list of resources to look for, when
the client requests an index of the directory by specifying a / at the end of
the directory name. Local-url is the (%-encoded) URL of a document on the
server relative to the requested directory; it is usually the name of a file
in the directory. Several URLs may be given, in which case the server will
return the first one that it finds. If none of the resources exist and the
I<Indexes> option is set, the server will generate its own listing of the
directory.

=head2 DirectorySlash

     DirectorySlash On

The I<DirectorySlash> directive determines, whether or not to fixup URLs
pointing to a directory or not. With this enabled (which is the default), if a
user requests a resource without a trailing slash, which points to a directory,
the user will be redirected to the same resource, but with trailing slash.

=head2 IndexXSLT

     IndexXSLT /simple.xslt

The I<IndexXSLT> directive sets the name of the file that will be used as the
XSLT for the index listing.

=head2 FileTypesFilename

=head1 XSLT STYLESHEET

The XSLT stylesheet will default to I<index.xslt> in the DocumentRoot of the
website. This can be changed using the I<IndexXSLT> directive. 

An example I<index.xslt> file is bundled with this module in the I<examples/>
directory.

=head1 SEE ALSO

L<Apache::AutoIndex>,
L<http://httpd.apache.org/docs/2.2/mod/mod_autoindex.html>,
L<http://httpd.apache.org/docs/2.2/mod/mod_dir.html>,
examples/*, L<http://bb-207-42-158-85.fallbr.tfb.net/>

=head1 VERSION

$Id$

=head1 AUTHOR

Nicola Worthington <nicolaw@cpan.org>

L<http://perlgirl.org.uk>

If you like this software, why not show your appreciation by sending the
author something nice from her
L<Amazon wishlist|http://www.amazon.co.uk/gp/registry/1VZXC59ESWYK0?sort=priority>? 
( http://www.amazon.co.uk/gp/registry/1VZXC59ESWYK0?sort=priority )

With special thanks to Jennifer Beattie for helping develop the example XSLT
stylesheets, and writing the I<examples/RegFileTypes.cs> "registered file type"
data and icons extraction program for Windows.

With special thanks to the authors of
L<http://httpd.apache.org/docs/2.2/mod/mod_autoindex.html> from which some
documentation taken.

=head1 COPYRIGHT

Copyright 2006 Nicola Worthington.

This software is licensed under The Apache Software License, Version 2.0.

L<http://www.apache.org/licenses/LICENSE-2.0>

=cut

__END__


