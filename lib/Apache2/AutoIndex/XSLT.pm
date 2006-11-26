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

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

use MD5;
use mod_perl2;
use Colloquy::Data qw(:all);

require Exporter;

@ISA = qw(Exporter AutoLoader);
@EXPORT = qw();
$VERSION = '1.13' || sprintf('%d.%02d', q$Revision: 531 $ =~ /(\d+)/g);

# Test for the version of mod_perl, and use the appropriate libraries
require Apache2::Access;
require Apache2::Connection;
require Apache2::Log;
require Apache2::RequestRec;
require Apache2::RequestUtil;
use Apache2::Const -compile => qw(HTTP_UNAUTHORIZED OK DECLINED);

# Handles Apache requests
sub handler {
	my $r = shift;

	my ($result, $password) = $r->get_basic_auth_pw;
	return $result if $result;

	my $user = $r->user;
	my $users_lua = $r->dir_config('users_lua') || '/usr/local/colloquy/data';
	my $allowaltauth = $r->dir_config('AllowAlternateAuth') || 'no';

	# remove the domainname if logging in from winxp
	## Parse $name's with Domain\Username
	my $domain = '';
	if ($user =~ m|(\w+)[\\/](.+)|) {
		($domain, $user) = ($1, $2);
	}

	# Check that the username doesn't contain characters
	# denied by Colloquy in main.lua
	if ($user =~ /\[\!\;\'\:\@\?\,\`\.\]\s/) {
		$r->note_basic_auth_failure;
		$r->log_error(
			"user $user: invalid username contains disallowed characters ",
			$r->uri);
		return (lc($allowaltauth) eq "yes" ? Apache2::Const::DECLINED : Apache2::Const::HTTP_UNAUTHORIZED);
	}

	# Check we have a password
	unless (length($password)) {
		$r->note_basic_auth_failure;
		$r->log_error("user $user: no password supplied for URI ", $r->uri);
		return Apache2::Const::HTTP_UNAUTHORIZED;
	}

	# Read the database
	my $users = {};
	eval {
		($users) = Colloquy::Data::users($users_lua);
	};

	# Check we can read the database file
	if ($@) {
		$r->note_basic_auth_failure;
		$r->log_error(
			"user $user: unable to read users_lua database '$users_lua': $@ at URI ",
			$r->uri);
		return (lc($allowaltauth) eq "yes" ? Apache2::Const::DECLINED : Apache2::Const::HTTP_UNAUTHORIZED);
	}

	# Check we have found that user
	unless (exists $users->{"$user"}->{password2} || exists $users->{"$user"}->{password}) {
		$r->note_basic_auth_failure;
		$r->log_error(
			"user $user: no valid user found for URI ",
			$r->uri);
		return (lc($allowaltauth) eq "yes" ? Apache2::Const::DECLINED : Apache2::Const::HTTP_UNAUTHORIZED);
	}

	# Now check the password
	my $db_password_hash = $users->{"$user"}->{password2} || $users->{"$user"}->{password} || '_no_db_passd_';
	my $our_password_hash = MD5->hexhash("$user$password") || '_no_usr_passd_';
	if ($our_password_hash eq $db_password_hash) {
		return Apache2::Const::OK;
	} else {
		$r->log_error(
			"user $user: invalid password for URI ",
			$r->uri);
		return (lc($allowaltauth) eq "yes" ? Apache2::Const::DECLINED : Apache2::Const::HTTP_UNAUTHORIZED);
	}

	# Otherwise fail
	return (lc($allowaltauth) eq "yes" ? Apache2::Const::DECLINED : Apache2::Const::HTTP_UNAUTHORIZED);
}

1;

=pod

=head1 NAME

Apache2::AutoIndex::XSLT - XSLT Based Directory Listings

=head1 SYNOPSIS

=head1 DESCRIPTION

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

=head1 COPYRIGHT

Copyright 2006 Nicola Worthington.

This software is licensed under The Apache Software License, Version 2.0.

L<http://www.apache.org/licenses/LICENSE-2.0>

=cut

__END__


