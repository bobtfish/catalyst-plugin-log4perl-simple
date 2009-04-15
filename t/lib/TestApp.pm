package TestApp;
use Moose;
extends 'Catalyst';

with 'Catalyst::Plugin::Log4Perl::Simple';

__PACKAGE__->config( name => 'TestApp', log4perl => $ENV{TEST_LOG4PERL} );
__PACKAGE__->setup;

1;
