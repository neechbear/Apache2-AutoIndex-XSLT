use strict;
use warnings FATAL => 'all';
  
use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest 'GET_BODY';
  
my @options = (
		'<option name="ReadmeName" value="FOOTER" />',
		'<option name="HeaderName" value="HEADER" />',
		'<option name="IndexStyleSheet" value="/index.xslt" />',
		'<option name="DirectoryIndex" value="index.html" />',
		'<option name="DirectoryIndex" value="index.shtml" />',
		'<option name="RenderXSLTEnvVar" value="RenderXSLT" />',
		'<option name="FileTypesFilename" value="filetypes.dat" />',
		'<option name="DefaultIcon" value="/icons/__unknown.png" />',
		'<option name="RenderXSLT" value="0" />',
	);

plan tests => scalar(@options);
  
my $url = '/';
my $data = GET_BODY $url ;

for (@options) {
	my ($option) = $_ =~ /name="(.+?)"/;
	(my $regex = $_) =~ s/\./\\./;
	ok t_cmp(
		$data,
		qr{$regex},
		"option $option"
	);
}

