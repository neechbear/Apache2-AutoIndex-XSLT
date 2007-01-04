# $Id$

use Test::More;
eval "use Test::Pod::Coverage 1.00";
plan skip_all => "Test::Pod::Coverage 1.00 required for testing POD Coverage" if $@;
all_pod_coverage_ok({
		also_private => [ qr/^[A-Z_]+$/ ],
		trustme => [ qw(handler
			status add_to_key build_attributes comify defaults dir_xml
			dump_apache_configuration file_mode file_type get_config
			glob2regex icon_by_extension merge push_val push_val_on_key
			set_val stat_file xml_header xml_options ) ]
	}); #Ignore all caps

1;

