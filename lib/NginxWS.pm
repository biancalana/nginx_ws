package NginxWS;
use Mojo::Base 'Mojolicious';

use Data::Dumper;

use File::Path qw(remove_tree);


$|++;

# This method will run once at server start
sub startup {
  my $self = shift;

  my $config = $self->plugin('Config'=> { file => 'etc/system.conf' });


  #
  # Helpers
  #
  $self->helper('ok' => sub {
    my ($c, $msg) = @_;
    $c->app->log->info($msg);

    $c->respond_to(
      json  => { json => {code => $self->config->{code}->{OK}}},
      any   => { text => sprintf("code=%d", $self->config->{code}->{OK})}
    );
  });


  $self->helper('nok' => sub {
    my ($c, $err_msg) = @_;
    $c->app->log->error($err_msg);

    if ( $c->stash->{temp_dir} && -d $c->stash->{temp_dir} ) {
        remove_tree($c->stash->{temp_dir})  if -d $c->stash->{temp_dir};
    }

    $c->respond_to(
      json  => { json => {code => $self->config->{code}->{NOK}, status => $err_msg}},
      any   => { text => sprintf("code=%d\nstatus=%s", $self->config->{code}->{NOK}, $err_msg)}
    );
  });


  #
  # Router
  #
  my $r = $self->routes->under('/' => sub {

    my $c = shift;


    # Save session data
    $c->stash(ip    => $c->tx->remote_address);
    $c->stash(route => $c->url_for);

    $c->app->log->format(sub {
      my ($time, $level, @lines) = @_;

      my $localtime_str = localtime($time);

      return(sprintf("[%s] [%s] [%s:%s] [%s] [%s] %s\n", $localtime_str, $level, $c->stash->{route}, $c->stash->{ip}, join("\n", @lines)));
    });
  });

  #
  # Normal route to controller
  #
=json_add_cfg_example
   "{http":{
      "upstream":{
         "name":"backend1",
         "servers":[
            {
               "addr":"192.168.10.1",
               "weight":"5"
            },
            {
               "addr":"192.168.1.1",
               "weight":"1"
            },
            {
               "addr":"192.168.100.1",
               "weight":"1",
               "down":"1"
            },
            {
               "addr":"192.168.200.1",
               "weight":"12",
               "backup":"1"
            }
         ]
      },
      "server":{
         "name":"www.zip.net",
         "location":[
            {
               "name":"/"
            },
            {
               "name":"/etc/passwd",
               "proxy_pass":"http://http_backend"
            }
         ]
      }
   }
}
=cut
  $r->post('/cfg/save')->to('cfg#save');
  $r->post('/cmd/run')->to('cmd#run');
}

1;
