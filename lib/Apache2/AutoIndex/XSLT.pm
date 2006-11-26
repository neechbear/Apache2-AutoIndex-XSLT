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
no strict qw(subs);
use vars qw($VERSION);
#use mod_perl2;
use Apache2::RequestRec qw();
use Apache2::Const -compile => qw(DIR_MAGIC_TYPE DECLINED);

$VERSION = '0.00' || sprintf('%d.%02d', q$Revision: 531 $ =~ /(\d+)/g);

# Let's deal with this another time shall we?
#if (mod_perl2->module('Apache::Status')){
#	Apache::Status->menu_item('AutoIndex' => sprintf('%s status',__PACKAGE__), \&status);
#}

sub handler {
	my $r = shift;
	return DECLINED unless $r->content_type && $r->content_type eq DIR_MAGIC_TYPE;

	

}

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


