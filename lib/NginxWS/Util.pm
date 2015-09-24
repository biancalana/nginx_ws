
package NginxWS::Util;

use warnings;
use strict;

use Data::Dumper;

use File::Copy::Recursive qw(dircopy);
use File::Temp qw(tempdir);

use Try::Tiny;


#============================================================
# Create a symlink to make that config default
#============================================================
sub CommitCFG {

  my ( $self, $new_conf_dir );

  $self         = shift;
  $new_conf_dir = $self->stash->{temp_dir};

  unless ( -d $new_conf_dir ) {
    $self->app->log->error("invalid new_conf_dir($new_conf_dir)");
    return;
  }

  unless ( -l $self->config->{nginx_conf_dir} ) {
    $self->app->log->error(sprintf("current config dir(%s) isn't a link !", $self->config->{nginx_conf_dir}));
    return;
  }

  unless ( unlink($self->config->{nginx_conf_dir}) ) {
    $self->app->log->error(sprintf("unlink(%s), $!", $self->config->{nginx_conf_dir}));
    return;
  }

  unless ( symlink($new_conf_dir, $self->config->{nginx_conf_dir}) ) {
    $self->app->log->error(sprintf("link(%s, %s), $!", $new_conf_dir, $self->config->{nginx_conf_dir}));
    return;
  }

  $self->app->log->error(sprintf("config committed (%s)", $new_conf_dir));

  return(1);
}


#============================================================
# Copy actual config on a tempdir and return that path
#============================================================
sub MakeEnvironment {

  my ( $self, $temp_dir, $err );

  $self = shift;

  #$self->app->log->debug(Dumper($self->config));

  try {
    $temp_dir = tempdir($self->config->{tmp_dir});
  } catch {
    $self->app->log->error("tempdir(), $_");
    $err++;
  };
  return  if $err;

  try {
    my $current_config_dir = readlink($self->config->{nginx_conf_dir});
    $self->stash(current_config_dir => $current_config_dir);

  } catch {
    $self->app->log->error(sprintf("readlink(%s), $_", $self->config->{nginx_conf_dir}));
    $err++;
  };
  return  if $err;

  unless ( dircopy(sprintf("%s/*", $self->config->{nginx_conf_dir}), $temp_dir) ) {
    $self->app->log->error(sprintf("dircopy(%s/*, %s), %s", $self->config->{nginx_conf_dir}, $temp_dir, $!));
    return;
  }

  $self->stash(temp_dir => $temp_dir);

  return(1);
}

#============================================================
#
#============================================================
sub ReloadCFG {

  my ( $self, $command, $res );

  $self = shift;

  $command = sprintf("%s -s reload", $self->config->{nginx_bin});

  $res = `$command 2>&1`;

  $self->app->log->debug(sprintf("command(%s) code(%s) %s", $command, $?, $res));

  return(1) unless($?);
}

#============================================================
# Re-create symlink pointing to original configuration
#============================================================
sub RollbackCFG {

  my ( $self, $working_conf_dir );

  $self             = shift;
  $working_conf_dir = $self->stash->{current_config_dir};

  unless ( -d $working_conf_dir ) {
    $self->app->log->error("invalid conf_dir($working_conf_dir)");
    return;
  }

  if ( -l $self->config->{nginx_conf_dir} ) {
    unlink($self->config->{nginx_conf_dir});
  }

  unless ( symlink($working_conf_dir, $self->config->{nginx_conf_dir}) ) {
    $self->app->log->error(sprintf("link(%s, %s), $!", $working_conf_dir, $self->config->{nginx_conf_dir}));
    return;
  }

  $self->app->log->error(sprintf("config rollback (%s)", $working_conf_dir));

  return(1);
}

#============================================================
#
#============================================================
sub TestCFG {


  my ( $self, $temp_dir );

  $self     = shift;
  $temp_dir = $self->stash->{temp_dir};

  unless ( -d $temp_dir ) {
    $self->app->log->error("tempdir($temp_dir), does not exists");
    return;
  }

  unless ( -f "$temp_dir/nginx.conf" ) {
    $self->app->log->error("$temp_dir/nginx.conf, does not exists");
    return;
  }

  my ( $command, $res );

  $command = sprintf("%s -t -c %s/nginx.conf", $self->config->{nginx_bin}, $temp_dir);

  $res = `$command 2>&1`;

  # only complain on syntax error !
  if ( $? != 0 && $res !~ /syntax is ok/m ) {
    $self->app->log->error(sprintf("command(%s), return_code(%d)", $command, $?));

    foreach my $log_line ( split(/\n/, $res) ) {
      $self->app->log->error($log_line);
    }
    return((0, $res));
  }

  return(1);
}

#============================================================
#
#============================================================
sub WriteFile {

  my ( $path, $content );

  $path     = shift;
  $content  = shift;

  #$logger->debug(sub { sprintf("path(%s) content(%s)", $path, $content)});

  #return  if -f $path;

  die("open($path), $!")  unless open(FILE, ">$path");

  print FILE $content;

  close(FILE);

  return(1);
}

1;
