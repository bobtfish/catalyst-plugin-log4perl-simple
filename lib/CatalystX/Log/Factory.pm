package CatalystX::Log::Factory;
use Moose::Role;
use namespace::clean -except => 'meta';

# Basic role for factories which build an instance of a log class

#requires qw/setup_finalize _build_logger_args/;

before 'setup_finalize' => sub {
    my $self = shift;
    my $class = blessed($self) || $self;
    $class->log( $self->_build_logger );
};

sub _build_logger {
    my $self = shift;
    my $class = $self->config->{'Log::Factory'}->{class};
    $class->new($self->_build_logger_args);
}

1;

