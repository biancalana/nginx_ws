package NginxWS::Controller::Cfg;
use Mojo::Base 'Mojolicious::Controller';


use NginxWS::Util;

use Data::Dumper;

use Try::Tiny;

my %CfgBuilder = ( http   => { server   => \&BuildCfg_SERVER,
                              upstream => \&BuildCfg_UPSTREAM },
                   stream => ( server   => \&BuildCfg_SERVER,
                              upstream => \&BuildCfg_UPSTREAM ));

#
#
#
sub save {

  my ( $self, $app, $tx, $json );

  $self = shift;
  $app  = $self->app;
  $tx   = $self->tx;
  $json = $tx->req->json;

  # only accept json input
  return $self->nok("invalid json")  unless $json;

  #$app->log->debug(">>>>>>>>>>>" .   $self->stash->{'mojo.started'});

  #
  # Copy current config before apply changes
  #
  unless ( NginxWS::Util::MakeEnvironment($self) ) {
    return $self->nok("internal error");
  }

  #
  # Loop on config received and build final format
  #
  foreach my $service_layer ( keys %{$json} ) {

    $app->log->debug("service_layer($service_layer)");

    foreach my $cfg_type ( keys %{$json->{$service_layer}} ) {

      my ( $cfg_path, $err );

      $app->log->debug("\tservice_layer($service_layer) cfg_type($cfg_type)");

      $cfg_path = sprintf("%s/%s/%s", $self->stash->{temp_dir}, $service_layer, $cfg_type);

      #
      # Parse Json, build and write config
      try {
        if ( ref($json->{$service_layer}->{$cfg_type}) eq 'ARRAY' ) {
          foreach ( @{$json->{$service_layer}->{$cfg_type}} ) {
            $CfgBuilder{$service_layer}{$cfg_type}($cfg_path, $_);
          }
        } else {
          $CfgBuilder{$service_layer}{$cfg_type}($cfg_path, $json->{$service_layer}->{$cfg_type});
        }
      } catch {
        $err = $_;
      };

      return $self->nok("invalid config, " . $err)  if $err;
    }
  }

  #
  # Test new config
  #
  my ( $return_code, $err_msg ) = NginxWS::Util::TestCFG($self);

  unless ( $return_code ) {
    return $self->nok("invalid config, " . $err_msg);
  }

  #
  # Rename new config dir
  #
  unless ( NginxWS::Util::CommitCFG($self) ) {
    return $self->nok("Internal error committing config");
  }

  #
  # Reload NGINX
  #
  unless ( NginxWS::Util::ReloadCFG($self) ) {
    unless ( NginxWS::Util::RollbackCFG($self) ) {
      return $self->nok("Internal error recovering config");
    }
    return $self->nok("Internal error reloading config");
  }

  return $self->ok("Ok");
}

#
#
#
sub BuildCfg_UPSTREAM {

  my ( $temp_dir, $cfg );

  $temp_dir = shift;
  $cfg      = shift;

  unless ( $cfg->{name} =~ /^[\w\.\-]+$/ ) {
    die "invalid upstream name";
  }

  my $out = "upstream $cfg->{name} {\n";
  foreach my $server ( @{$cfg->{servers}} ) {

    # server address is defined and hostname or ip addr
    unless ( $server->{addr} and
                ( $server->{addr} =~ /^\{3}\.\{3}\.\{3}\.\{3}$/ or
                  $server->{addr} =~ /^[\w\-\.]+$/ ) ) {
      die "invalid server address";
    }
    $out .= "\tserver $server->{addr}";

    # fail_timeout defined and integer
    if ( $server->{fail_timeout} ) {
      die "invalid server fail_timeout" unless $server->{fail_timeout} =~ /^\d{1,2}$/;
      $out .= " fail_timeout=$server->{fail_timeout}";
    }

    # max_fails defined and integer
    if ( $server->{max_fails} ) {
      die "invalid server max_fails" unless $server->{max_fails} =~ /^\d{1,2}$/;
      $out .= " max_fails=$server->{max_fails}";
    }

    # slow_start defined and integer
    if ( $server->{slow_start} ) {
      die "invalid server slow_start" unless $server->{slow_start} =~ /^\d{1,2}$/;
      $out .= " slow_start=$server->{slow_start}";
    }

    # weight defined and integer
    if ( $server->{weight} ) {
      die "invalid server weight" unless $server->{weight} =~ /^\d{1,4}$/;
      $out .= " weight=$server->{weight}";
    }

    # down defined
    if ( $server->{backup} ) {
      $out .= " backup";
    }

    # down defined
    if ( $server->{down} ) {
      $out .= " down";
    }

    # resolve defined
    if ( $server->{resolve} ) {
      $out .= " resolve";
    }

    $out  .= ";\n";
  }
  $out    .= "}\n";

  # Write temp file with given config
  die unless NginxWS::Util::WriteFile("$temp_dir-$cfg->{name}.conf", $out);
}

#
#
#
sub BuildCfg_SERVER {

  my ( $temp_dir, $cfg );

  $temp_dir = shift;
  $cfg      = shift;

  my $out = "server {\n";

  # server address is defined and hostname or ip addr
  unless ( $cfg->{name} && $cfg->{name} =~ /^[\w\.\-]+$/ ) {
    die "invalid server name";
  }

  $out .= "\tserver_name $cfg->{name};\n";


  # server address is defined and hostname or ip addr
  if ( $cfg->{port} ) {
    unless ( $cfg->{port} =~ /^\{5}$/ && $cfg->{port} >= 65535 ) {
      die "invalid port";
    }
  } else {
    $cfg->{port} = 80;
  }

  $out .= "\tlisten $cfg->{port};\n";

  foreach my $location ( @{$cfg->{location}} ) {

    #
    unless ( $location->{name} ) {
      die "invalid server location";
    }
    $out .= "\tlocation $location->{name} {\n";

    # proxypass defined
    if ( $location->{proxy_pass} ) {
      $out .= "\t\tproxy_pass $location->{proxy_pass};\n";
    }

    $out  .= "\t}\n\n";
  }
  $out    .= "}\n\n";

  # Write temp file with given config
  die unless NginxWS::Util::WriteFile("$temp_dir-$cfg->{name}.conf", $out);
}

1;
