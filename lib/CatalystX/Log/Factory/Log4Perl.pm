package CatalystX::Log::Factory::Log4Perl;
use Moose::Role;
use Sub::Recursive;
use namespace::clean -except => 'meta';

with 'CatalystX::Log::Factory';

#requires qw/setup_finalize/;

before 'setup_finalize' => sub {
    my $self = shift;
    my $logger_class = $self->config->{'Log::Factory'}->{class}
        ||= 'Catalyst::Log::Log4perl';
    Class::MOP::load_class($logger_class);
};

sub _build_logger_args { # This method is epicly too long in my opinion!
    my $self = shift;
      my ( $error_logger, %log4perl_conf, %log4perl_args, %error_logger );
my %ignore_classes;
my @error_loggers;
my %email_appender;
  my $conf = exists $self->config->{log4perl} ?
    $self->config->{log4perl} : undef;

  if ( ref $conf eq 'HASH' ) {
    $error_logger  =    delete $conf->{error_logger} || undef;
    %log4perl_args = %{ delete $conf->{options}      || {}    };
    my $visit = recursive {
      my ( $base, $path ) = @_;
      if ( ref $_[0] eq 'HASH' ) {
        for my $key ( keys %{ $_[0] } ) {
          $REC->( $_[0]->{ $key }, join( '.', $path, $key ) );
        }
      } elsif ( ref $_[0] eq 'ARRAY' ) {
        $REC->( join( ', ', @{ $_[0] } ), $path );
      } else {
        $path =~ s/appender\.(.+)\.class/appender.${1}/;
        $path =~ s/threshold$/Threshold/;
        $path =~ s/\.pattern$/.ConversionPattern/;
        $path =~ s/root_logger$/rootLogger/;
        $log4perl_conf{ $path } = $_[0];
      }
    };
    $visit->( $conf, 'log4perl' );
  }

  my $find_logger_conf = sub{
    my @default_paths = grep{ defined and not ref }
      ( $conf, qw/log4perl_local.conf log4perl.conf/ );
    my ( $conf ) = grep{ -r $self->path_to( $_ )->stringify } @default_paths;
    return $conf;
  };

  my %default_appender;
  my $default_log_level  = $self->debug ? 'DEBUG' : 'WARN';
  {
    my $class  = -t STDERR ? 'ScreenColoredLevels' : 'Screen';
    my $prefix = 'log4perl.appender';
    my $app    = \ %default_appender;
    $app->{"log4perl.rootLogger"} = "${default_log_level}, DefaultAppender";
    $app->{"${prefix}.DefaultAppender"} = 'Log::Log4perl::Appender::Screen';
    $app->{"${prefix}.DefaultAppender.layout"}= 'PatternLayout';
    $app->{"${prefix}.DefaultAppender.layout.ConversionPattern"} =
      '[%p] %c %d %F:%L %n%m%n';
  }

  %log4perl_conf = %default_appender
    unless %log4perl_conf or $find_logger_conf->();

  my @config_errors;

  if ( $error_logger ) {
    my $appender = ref $error_logger eq 'HASH' ?
      delete $error_logger->{appender} || 'auto' : $error_logger;

    if ( $appender eq 'off' ) {

      $self->log->info( "Turning off extended error logging" );

    } elsif ( $appender eq 'auto' ) {
    
      my $name = 'CatalystAutomaticErrorAppender';
      $log4perl_conf{"log4perl.appender.${name}"} =
        delete $error_logger->{class} || 'Log::Dispatch::Email::MailSend';
      $log4perl_conf{"log4perl.appender.${name}.to"} =
        delete $error_logger->{recipient}
          or die "Recipient needed for appender";
      $log4perl_conf{"log4perl.appender.${name}.Threshold"} =
        delete $error_logger->{threshold} || 'ERROR';
      $log4perl_conf{"log4perl.appender.${name}.subject"} =
        delete $error_logger->{subject} ||
          sprintf( '[%s] Internal server error', $self->config->{name} );
      $log4perl_conf{"log4perl.appender.${name}.layout"} =
        delete $error_logger->{layout} || 'PatternLayout';
      $log4perl_conf{"log4perl.appender.${name}.layout.ConversionPattern"} =
        delete $error_logger->{pattern} || '[%p] %F:%L %n%m%n%n';
      push @config_errors, "Unknown keys in error_logger configuration:" .
        join( ', ', keys %{ $error_logger } );

      # append the automatically configured append to the root logger
      $log4perl_conf{"log4perl.rootLogger"} = join(
        ', ', $log4perl_conf{"log4perl.rootLogger"} || 'ERROR', $name
      );
      @error_loggers = ( $name );
    } else {
      @error_loggers = ( split /,\s?/, $appender );
    }

    $self->log->warn(
      "Unknown/invalid error_logger keys:",
      Dumper( keys %{ $error_logger } )
    ) if ref $error_logger and %{ $error_logger };
  }

  for my $logger ( @error_loggers ) {
    my $l4p_appender = Log::Log4perl->appenders->{ $logger };
    my $appender = eval{ $l4p_appender->{appender} }
      or die "Can't find $logger in ". Dumper( Log::Log4perl->appenders );
    next unless blessed $appender and $appender->isa('Log::Dispatch::Email');
    $email_appender{ $logger } = $appender;
  }

  if ( %log4perl_conf ) {
      return( \%log4perl_conf, %log4perl_args );
    } else {
      my $config_path = $find_logger_conf->();
      $self->log->info( "Falling back to property file ${config_path}" );
      return( $config_path, watch_delay => 30 );
    }
};

1;

