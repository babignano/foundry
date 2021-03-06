#!/usr/bin/perl
#use strict;
use warnings;

use Data::Dumper qw(Dumper);
use Data::Structure::Util qw/unbless/;
use DateTime qw();
use DateTime::Format::Strptime qw();
use HTTP::Headers;
use HTTP::Request::Common; 
use HTTP::Request; 
use JSON;
use LWP::Simple; 
use LWP::UserAgent; 
use MIME::Base64;
use Plack::Builder;
use Plack::Request;
use REST::Client;
use Storable;
use String::Truncate qw(elide);
use Time::HiRes qw(gettimeofday tv_interval);
use URI::Escape;
use XML::Simple;
$Data::Dumper::Sortkeys = 1;
 
my $app = sub {
  my $env = shift;
  my ($html, $dist, $latlong);

  my $request = Plack::Request->new($env);
 
  return [ 404, ['Content-Type' => 'text/html'], [ '404 Not Found' ] ] unless $request->path eq '/';

  if ($request->param('latlong')) {
      $latlong = $request->param('latlong') || "-33.885193,151.209399";
  }

  if ($request->param('dist')) {
      $dist =  $request->param('dist');
  }

  my @vals1 = split(',',$latlong);
  $html = getContent($vals1[0],$vals1[1],$dist);

  return [
    '200',
    [ 'Content-Type' => 'text/json' ],
    [ $html ],
  ];
};

builder {
	enable "JSONP", callback_key => 'callback';
	$app;
};

sub getContent {

  my $lat      = $_[0];
  my $long     = $_[1];
  my $distance = $_[2];
  my $offset   = $_[3];

  my $headers = {Accept => 'application/json'};
  my $client = REST::Client->new();

  ##
  # Get the CAPI data
  ##

  $client->setHost('http://cdn.newsapi.com.au');

  my $start = [gettimeofday()];
  $client->GET(
      'content/v1/?format=json&geoDistance=' . $lat . ',' . $long . ":" . $distance . '&type=news_story&origin=methode&includeRelated=false&includeBodies=true&includeFutureDated=false&pageSize=10&offset=0&maxRelatedLevel=1&api_key=r7j3ufg79yqkpmszf73b8ked',
      $headers
  );
  print STDERR "News API call took " . tv_interval($start) . "\n";

  my @resset;
  my $res2;

  my $response = from_json($client->responseContent());

  my $results = $response->{'results'};

  foreach my $result (@$results){
    my $resultSimple;
    $resultSimple->{'headline'}            =  $result->{'title'};
    $resultSimple->{'standfirst'}          =  $result->{'standFirst'};
    $resultSimple->{'paidStatus'}          =  $result->{'paidStatus'};
    $resultSimple->{'originalSource'}      =  'news';
    $resultSimple->{'thumbnail'}{'uri'}    =  $result->{'thumbnailImage'}{'link'};
    $resultSimple->{'thumbnail'}{'width'}  =  $result->{'thumbnailImage'}{'width'};
    $resultSimple->{'thumbnail'}{'height'} =  $result->{'thumbnailImage'}{'height'};
    $resultSimple->{'url'}                 = $result->{'link'};
    # only grab the closest geopoint
    my %pins;
    for my $location (@{$result->{'locationGeoPoints'}}) {
      my $pinDist = distance($lat, $long, $location->{latitude}, $location->{longitude});
      $pins{$pinDist} = $location;
    }
    my @keys = sort {$a <=> $b} keys %pins;
    $resultSimple->{'location'}            =  [$pins{$keys[0]}];

    #print "Array: " . Dumper($resultSimple) . "\n";

    push @resset, $resultSimple;
    #print "help " . $resset[$count] . "\n";
    
  }

  ## 
  # Add the REA stuff in
  ##

  my $ua = LWP::UserAgent->new;
  my $json = JSON->new;
  my $strp = DateTime::Format::Strptime->new(
        pattern   => '%Y-%m-%dT%H:%M:%S',
        locale    => 'en_AU',
        time_zone => 'Australia/Sydney',
  );

  my $base = 'http://trial1060.api.mashery.com/v1/services/listings/search?query=';
  my $apiKey = 'ug5ddujnfet3vuahkwra8ua8';

  my $channel = uri_escape('"channel":"buy"');
  my $pageNum = 1;
  my $page = uri_escape('"page":"' . $pageNum . '"');
  my $pageSize = uri_escape('"pageSize":"20"');
  my $filter = uri_escape('"filters":{"surroundingSuburbs":false}');
  my $radial = uri_escape('"radialSearch":{"center":[' . "$lat,$long" . ']}');

  my $url = "${base}{$channel,$page,$pageSize,$filter,$radial}&api_key=$apiKey";

  my $reaResults = cache_get('rea', $lat, $long, $distance);

  if (!defined $reaResults) {
    $start = [gettimeofday()];
    my $res = $ua->get($url);
    print STDERR "REA API call took " . tv_interval($start) . "\n";

    if ($res->is_success) {
      my $listings = $json->decode($res->content);

      foreach my $listing (@{$listings->{tieredResults}->[0]->{results}}) {
        next unless $listing->{inspectionsAndAuctions};

        foreach my $inspection (@{$listing->{inspectionsAndAuctions}}) {
          # We only care about auctions
          next unless $inspection->{auction};

          # We only care about auctions in our specified radius
          next unless (distance($lat, $long, $listing->{address}->{location}->{latitude}, $listing->{address}->{location}->{longitude}) <= $distance);

          # We only care about auctions in the next week
          my $auctionTime = $strp->parse_datetime($inspection->{startTime});
          my $days = $auctionTime->subtract_datetime(DateTime->now());
          next unless $days->in_units('days') <= 7;

          my $standfirst = $listing->{description};
          $standfirst =~ s|<.+?>||g;

          push @$reaResults, {
            url => $listing->{'_links'}->{short}->{href},
            headline => "Auction: " .
                   $inspection->{dateDisplay} .
                   ", " . $inspection->{startTimeDisplay} .
                   ". " . $listing->{title},
            standfirst => elide($standfirst, 150, {at_space => 1}),
            paidStatus => 'NON_PREMIUM',
            originalSource => 'rea',
            location => [{
              latitude => $listing->{address}->{location}->{latitude},
              longitude => $listing->{address}->{location}->{longitude}
            }],
            thumbnail => {
              uri => $listing->{mainImage}->{server} . '/120x90' . $listing->{mainImage}->{uri},
              width => 120,
              height => 90,
            }
          };
        }
      }
      cache_set('rea', $reaResults, $lat, $long, $distance);
    }
    else {
      warn $res->status_line;
    }
  }

  push (@resset, @$reaResults);

  ##
  # Add in the traffic info
  ##

  my $incidentsUrl = 'http://livetraffic.rta.nsw.gov.au/traffic/hazards/incident-open.json';

  $start = [gettimeofday()];
  $res = $ua->get($incidentsUrl);
  print STDERR "Traffic API call took " . tv_interval($start) . "\n";

  if ($res->is_success) {
    my $incidents = $json->decode($res->content);

    foreach my $incident (@{$incidents->{features}}) {
      if (distance($lat, $long, $incident->{geometry}->{coordinates}->[1], $incident->{geometry}->{coordinates}->[0]) <= $distance) {
        push @resset, {
          url => 'https://www.livetraffic.com/',
          headline => $incident->{properties}->{displayName},
          standfirst => $incident->{properties}->{headline},
          paidStatus => 'NON_PREMIUM',
          originalSource => 'traffic',
          location => {
            latitude => $incident->{geometry}->{coordinates}->[1],
            longitude => $incident->{geometry}->{coordinates}->[0]
          },
          thumbnail => {
            uri => 'http://placehold.it/120x90',
            width => 120,
            height => 90,
          }
        };
      }
    }
  }

  ##
  # Add the tweets
  ##

  my $tweetResults = cache_get('twitter', $lat, $long, $distance);

  if (!defined $tweetResults) {

  	my $domain = 'search.gnip.com';
  	my $username = 'rchoi+gnip@twitter.com';
  	my $password = '#NewsFoundry';

  	my $term = '#NewsFoundry';

  	my $location = 'point_radius:[' . $long . ' ' . $lat . ' 3.0mi]';
  	$term = $term . ' ' . $location;

  	# below returns all tweets in last 30 days for rchoi
  	$term = uri_escape($term);
  	my $server_endpoint = "https://$domain/accounts/dpr-content/search/choi.json?publisher=twitter&query=$term&maxResults=10";

  	# below returns counts for term daily
  	# my $server_endpoint = "https://$domain/accounts/dpr-content/search/choi/counts.json?publisher=twitter&query=$term&bucket=day";

  	my $req = GET $server_endpoint;
  	$req->authorization_basic($username, $password);

    $start = [gettimeofday()];
  	my $agent = LWP::UserAgent->new;
  	my $resp = $agent->request($req); 
    print STDERR "Twitter API call took " . tv_interval($start) . "\n";

  	if ($resp->is_success) {
    	my $message = from_json($resp->decoded_content);

    	my $results = $message->{'results'};

      foreach my $result (@$results){

    	push @$tweetResults, {
              url => $result->{'link'},
              headline => $result->{'object'}{'summary'},
              standfirst => $result->{'object'}{'summary'},
              paidStatus => 'NON_PREMIUM',
              originalSource => 'twitter',
              location => [{
                latitude => $result->{'geo'}{'coordinates'}[0],
                longitude => $result->{'geo'}{'coordinates'}[1]
              }],
              thumbnail => {
                uri => $result->{'actor'}{'image'},
                width => 100,
                height => 100,
              }
            };
        }

    	#my $message = $resp->decoded_content;
    	#print "Received reply: " . Dumper($message) . "\n";
      cache_set('twitter', $tweetResults, $lat, $long, $distance);
  	}
  	else {
  	}
  }
  push (@resset, @$tweetResults);

  ## Add Eventful events

  my $eventResults = cache_get('eventful', $lat, $long, $distance);

  if (!defined $eventResults) {
    my $eventurl = "http://api.eventful.com/rest/events/search?app_key=DwG227bNxf2ZXbSS&keywords=books&location=$lat,$long&within=$distance&units=km&date=This+Week&page_size=10";

    $start = [gettimeofday()];
    $res = $ua->get($eventurl);
    print STDERR "Eventful API call took " . tv_interval($start) . "\n";

    if ($res->is_success) {
      my $xs = XML::Simple->new();    
      my $events = $xs->XMLin($res->content);

      foreach my $event (values %{$events->{events}->{event}}) {
        my $description = $event->{description};
        $description =~ s|<.+?>||g;

        my $eventImage;
        if ($event->{image}->{medium}->{url}) {
            $eventImage = {
              uri => $event->{image}->{medium}->{url},
              width => $event->{image}->{medium}->{width},
              height => $event->{image}->{medium}->{height}
            };
        }
        else {
            $eventImage = {
              uri => 'http://placehold.it/128x128',
              width => '128',
              height => '128'
            };
        }
        push @$eventResults, {
          url => $event->{url},
          headline => $event->{title},
          standfirst => elide($description, 150, {at_space => 1}),
          paidStatus => 'NON_PREMIUM',
          originalSource => 'eventful',
          location => [{
            latitude => $event->{latitude},
            longitude => $event->{longitude}
          }],
          thumbnail => $eventImage
        };
      }
      cache_set('eventful', $eventResults, $lat, $long, $distance);
    }
    else {
      print STDERR "Eventful failed: " . $res->status_line . "\n";
    }
  }

  push (@resset, @$eventResults);


## add in localshoppa

my $offerResults = cache_get('localshoppa', $lat, $long, $distance);

if (!defined $offerResults) {
  my $url = "http://api.localshoppa.com.au/2.0/55399b27333bfe0cfce9c0b0/Deal?latitude=$lat&order=closest&skip=0&radius=$distance&take=10&longitude=$long";
  
  $start = [gettimeofday()];
  my $res = $ua->get($url);
  print STDERR "LocalShoppa API call took " . tv_interval($start) . "\n";

  if ($res->is_success) {
      my $offers = $json->decode($res->content);
      foreach my $offer (@{$offers->{data}}) {
        push @$offerResults, {
            url => $offer->{'buynow_url'},
            headline => $offer->{title},
            standfirst => $offer->{brief_description},
            paidStatus => 'NON_PREMIUM',
            originalSource => 'shopping',
            location => [{
              latitude => $offer->{store}->{location}->{lat},
              longitude => $offer->{store}->{location}->{long}
            }],
            thumbnail => {
              uri => $offer->{thumbnail_url},
              width => 200,
              height => 150,
            }
          };
      }
      cache_set('localshoppa', $offerResults, $lat, $long, $distance);
  }
  else {
    warn $res->status_line;
  }
}

push (@resset, @$offerResults);


$res2->{'resultSet'} = \@resset;
$res2->{'resultSize'} = scalar @resset;

#print "Hash: " . Dumper($res2) . "\n";

return (to_json($res2, {utf8 => 1}));

}

sub distance {
  my ($lat1, $lon1, $lat2, $lon2) = @_;
  my $theta = $lon1 - $lon2;
  my $dist = sin(deg2rad($lat1)) * sin(deg2rad($lat2)) + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * cos(deg2rad($theta));
    $dist  = acos($dist);
    $dist = rad2deg($dist);
    $dist = $dist * 60 * 1.1515;
    $dist = $dist * 1.609344;
  return ($dist);
}

sub acos {
  my ($rad) = @_;
  my $ret = atan2(sqrt(1 - $rad**2), $rad);
  return $ret;
}

sub deg2rad {
  my ($deg) = @_;
  my $pi = atan2(1,1) * 4;
  return ($deg * $pi / 180);
}

sub rad2deg {
  my ($rad) = @_;
  my $pi = atan2(1,1) * 4;
  return ($rad * 180 / $pi);
}

sub cache_get {
  my ($source, $lat, $long, $distance) = @_;

  my $filename = "$source-$lat-$long-$distance.storable";
  my $arrayref;

  # Cache expiry set to 1 hour
  if (-e $filename && (stat($filename))[9] >= (time() - 3600)) {
    print STDERR "cache hit : $filename\n";
    $arrayref = retrieve($filename);
  }
  else {
    print STDERR "cache miss : $filename\n";
  }
  return $arrayref;
}

sub cache_set {
  my ($source, $data, $lat, $long, $distance) = @_;

  my $filename = "$source-$lat-$long-$distance.storable";
  store($data, $filename);
}
