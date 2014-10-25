package App::Netdisco::Web::Search;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Web 'sql_match';

hook 'before' => sub {
  # view settings for node options
  var('node_options' => [
    { name => 'stamps', label => 'Time Stamps', default => 'on' },
  ]);

  # view settings for device options
  var('device_options' => [
    { name => 'matchall', label => 'Match All Options', default => 'on' },
  ]);

  return unless (request->path eq uri_for('/search')->path
      or index(request->path, uri_for('/ajax/content/search')->path) == 0);

  foreach my $col (@{ var('node_options') }) {
      next unless $col->{default} eq 'on';
      params->{$col->{name}} = 'checked'
        if not param('tab') or param('tab') ne 'node';
  }

  foreach my $col (@{ var('device_options') }) {
      next unless $col->{default} eq 'on';
      params->{$col->{name}} = 'checked'
        if not param('tab') or param('tab') ne 'device';
  }
};

hook 'before_template' => sub {
  my $tokens = shift;

  # new searches will use these defaults in their sidebars
  $tokens->{search_node}   = uri_for('/search/node');
  $tokens->{search_device} = uri_for('/search/device');

  foreach my $col (@{ var('node_options') }) {
      next unless $col->{default} eq 'on';
      $tokens->{search_node}->query_param($col->{name}, 'checked');
  }

  foreach my $col (@{ var('device_options') }) {
      next unless $col->{default} eq 'on';
      $tokens->{search_device}->query_param($col->{name}, 'checked');
  }

  return unless (request->path eq uri_for('/search')->path
      or index(request->path, uri_for('/ajax/content/search')->path) == 0);

  # used in the device search sidebar template to set selected items
  foreach my $opt (qw/model vendor os_ver/) {
      my $p = (ref [] eq ref param($opt) ? param($opt)
                                          : (param($opt) ? [param($opt)] : []));
      $tokens->{"${opt}_lkp"} = { map { $_ => 1 } @$p };
  }
};

my $handler = sub {
    my $q = param('q');
    my ($tab) = splat;
    my $s = schema('netdisco');

    my $prefer = param('prefer');
    $prefer = ''
        unless defined $prefer and $prefer =~ m/^(?:device|node|vlan|port)$/;
    $tab ||= param('prefer');

    if (not $tab) {
        if (not $q) {
            return redirect uri_for('/')->path;
        }

        # pick most likely tab for initial results
        if ($q =~ m/^\d+$/) {
            $tab = 'vlan';
        }
        else {
            my $nd = $s->resultset('Device')->search_fuzzy($q);
            my ($likeval, $likeclause) = sql_match($q);

            if ($nd and $nd->count) {
                if ($nd->count == 1) {
                    # redirect to device details for the one device
                    return redirect uri_for('/device/details', {
                      q => $nd->first->ip,
                      f => '',
                    })->path_query;
                }

                # multiple devices
                $tab = 'device';
            }
            elsif ($s->resultset('DevicePort')
                     ->search({
                       -or => [
                         {name => $likeclause},
                         (length $q == 17 ? {mac => $q}
                                          : \['mac::text ILIKE ?', $likeval]),
                       ],
                     })->count) {

                $tab = 'port';
            }
        }

        # if all else fails
        $tab ||= 'node';
    }

    # used in the device search sidebar to populate select inputs
    my $model_list  = [ $s->resultset('Device')->get_distinct_col('model')  ];
    my $os_ver_list = [ $s->resultset('Device')->get_distinct_col('os_ver') ];
    my $vendor_list = [ $s->resultset('Device')->get_distinct_col('vendor') ];

    template 'search', {
      tabname => $tab,
      model_list  => $model_list,
      os_ver_list => $os_ver_list,
      vendor_list => $vendor_list,
    };
};

get '/search'   => require_login $handler;
get '/search/*' => require_login $handler;

true;
