package USPS::RateRequest;

use strict;
use Moose;
use XML::DOM;
use AnyEvent::HTTP::LWP::UserAgent;
use AnyEvent;
use Ouch;
use POSIX qw(ceil);
use XML::Simple;

has 'test_mode' => (
    is          => 'rw',
    default     => 0,
);

has prod_uri => (
    is          => 'rw',
    default     => 'http://production.shippingapis.com/ShippingAPI.dll'
);

has test_uri => (
    is          => 'rw',
    default     => 'http://testing.shippingapis.com/ShippingAPItest.dll',
);

has user_id => (
    is          => 'ro',
    required    => 1,
);

has password => (
    is          => 'ro',
    required    => 1,
);

has from => (
    is          => 'rw',
    isa         => 'Int',
    required    => 1,
);

has to => (
    is          => 'rw',
);

has service => (
    is          => 'rw',
    default     => 'all',
);

__PACKAGE__->meta()->make_immutable();


sub _generate_request_xml {
    my ($self, $boxes) = @_;
    my $rate_request_document = XML::DOM::Document->new();
    my $rate_request_element  = $rate_request_document->createElement(
        $self->domestic() ? 'RateV4Request' : 'IntlRateV2Request');

    # Note that these are required even for test mode transactions.
    $rate_request_element->setAttribute('USERID',   $self->user_id);
    $rate_request_element->setAttribute('PASSWORD', $self->password);
    $rate_request_document->appendChild($rate_request_element);

# needed for special services    
#    my $revision_element = $rate_request_document->createElement('Revision');
#    $revision_element->appendChild($rate_request_document->createTextNode(2));
#    $rate_request_element->appendChild($revision_element);

    foreach my $box (@{ $boxes }) {
        my $package_element = $rate_request_document->createElement('Package');
        $package_element->setAttribute('ID', $box->id);
        $rate_request_element->appendChild($package_element);

        if ($self->domestic) {
            my $service_element = $rate_request_document->createElement('Service');
            $service_element->appendChild($rate_request_document->createTextNode($self->service)); 
            $package_element->appendChild($service_element);

            my $zip_origin_element = $rate_request_document->createElement('ZipOrigination');
            $zip_origin_element->appendChild($rate_request_document->createTextNode($self->from));
            $package_element->appendChild($zip_origin_element);

            my $zip_destination_element = $rate_request_document->createElement('ZipDestination');
            $zip_destination_element->appendChild($rate_request_document->createTextNode($self->to));
            $package_element->appendChild($zip_destination_element);
        }

        my $weight = $box->calculate_weight;
        my $pounds = int($weight / 16);
        my $ounces = $weight % 16;

        my $pounds_element = $rate_request_document->createElement('Pounds');
        $pounds_element->appendChild($rate_request_document->createTextNode($pounds));
        $package_element->appendChild($pounds_element);

        my $ounces_element = $rate_request_document->createElement('Ounces');
        $ounces_element->appendChild($rate_request_document->createTextNode($ounces));
        $package_element->appendChild($ounces_element);

        unless ($self->domestic) {
            my $mail_type_element = $rate_request_document->createElement('MailType');
            $mail_type_element->appendChild($rate_request_document->createTextNode($box->mail_type));
            $package_element->appendChild($mail_type_element);
            
            my $gxg_element = $rate_request_document->createElement('GXG');
            my $pobox_flag_element = $rate_request_document->createElement('POBoxFlag');
            $pobox_flag_element->appendChild($rate_request_document->createTextNode($box->mail_pobox_flag));
            $gxg_element->appendChild($pobox_flag_element);
            my $gift_flag_element = $rate_request_document->createElement('GiftFlag');
            $gift_flag_element->appendChild($rate_request_document->createTextNode($box->mail_gift_flag));
            $gxg_element->appendChild($gift_flag_element);
            $package_element->appendChild($gxg_element);
            
            my $value_of_contents_element = $rate_request_document->createElement('ValueOfContents');
            $value_of_contents_element->appendChild($rate_request_document->createTextNode($box->value_of_contents));
            $package_element->appendChild($value_of_contents_element);            

            my $country_element = $rate_request_document->createElement('Country');
            $country_element->appendChild($rate_request_document->createTextNode($self->to));
            $package_element->appendChild($country_element);            

        }
        
        my $container_element = $rate_request_document->createElement('Container');
        $container_element->appendChild($rate_request_document->createTextNode($self->domestic ? $box->mail_container : 'RECTANGULAR'));
        $package_element->appendChild($container_element);

        my $oversize_element   = $rate_request_document->createElement('Size');
        $oversize_element->appendChild($rate_request_document->createTextNode($box->mail_size));
        $package_element->appendChild($oversize_element);

        my $width_element   = $rate_request_document->createElement('Width');
        $width_element->appendChild($rate_request_document->createTextNode($box->y));
        $package_element->appendChild($width_element);

        my $length_element   = $rate_request_document->createElement('Length');
        $length_element->appendChild($rate_request_document->createTextNode($box->x));
        $package_element->appendChild($length_element);

        my $height_element   = $rate_request_document->createElement('Height');
        $height_element->appendChild($rate_request_document->createTextNode($box->z));
        $package_element->appendChild($height_element);

        my $girth_element   = $rate_request_document->createElement('Girth');
        $girth_element->appendChild($rate_request_document->createTextNode($box->girth));
        $package_element->appendChild($girth_element);

        if ($self->domestic) {
            if ($self->service =~ /all/i and not defined $box->mail_machinable()) {
                $box->mail_machinable('False');
            }

    # trying to get special services working
            #my $special_services_element = $rate_request_document->createElement('SpecialServices');
            #my $insurance_element = $rate_request_document->createElement('SpecialService');
            #$insurance_element->appendChild($rate_request_document->createTextNode(1));
            #$special_services_element->appendChild($insurance_element);
            #$package_element->appendChild($special_services_element);

            if (defined $box->mail_machinable) {
                my $machine_element = $rate_request_document->createElement('Machinable');
                $machine_element->appendChild($rate_request_document->createTextNode($box->mail_machinable));
                $package_element->appendChild($machine_element);
            }
        }
        

    }
    return $rate_request_document->toString();
}

sub _generate_requests {
    my ($self, $boxes) = @_;
    my @requests = ();
    my @boxes = @{ $boxes };
    my $limit = 20; # the USPS service craps out if the XML document is too big, most likely due to it being URL encoded, rather than a post body
    my $pages = ceil( scalar(@boxes) / $limit );
    for (1..$pages) {
        my @temp = ();
        my $temp_limit = scalar @boxes;
        $temp_limit = $limit if $limit < $temp_limit;
        for (1..$temp_limit) {
            push @temp, shift @boxes;
        }
        push @requests, $self->_generate_request_xml(\@temp);
    }
    return \@requests;
}

sub _generate_uri {
    my $self = shift;
    return $self->test_mode ? $self->test_uri : $self->prod_uri;
}

sub request_rates {
    my ($self, $boxes) = @_;
    my @responses = ();
    my $cv = AnyEvent->condvar;
    $cv->begin(sub { shift->send($self->_handle_responses(\@responses)) });
    foreach my $request_xml (@{$self->_generate_requests($boxes)}) {
        $cv->begin;
        my $content = 'API=' . ($self->domestic ? 'RateV4' : 'IntlRateV2') . '&XML=' . $request_xml;
        my $ua = AnyEvent::HTTP::LWP::UserAgent->new;
        $ua->timeout(30);
        $ua->post_async($self->_generate_uri,
            Content_Type        => 'application/x-www-form-urlencoded',
            'content-length'    => CORE::length($request_xml),
            Content             => $content,
            )->cb(sub {
                push @responses, shift->recv;
                $cv->end;
            });
    }
    $cv->end;
    return $cv;
}

sub _handle_responses {
    my ($self, $responses) = @_;
    my %rates = ();
    foreach my $response (@{$responses}) {
        $self->_handle_response($response, \%rates);
    }
    unless (scalar keys %rates) {
        ouch 'No Rates', 'No rates were returned for your packages.';
    }
    return \%rates;
}

sub _handle_response {
    my ($self, $response, $rates) = @_;

    ### Keep the root element, because USPS might return an error and 'Error' will be the root element
    my $response_tree = XML::Simple::XMLin(
        $response->decoded_content,
        ForceArray => 0,
        KeepRoot   => 1
    );
    
    ### Discard the root element on success
    $response_tree = $response_tree->{RateV4Response} if (exists($response_tree->{RateV4Response}));
    $response_tree = $response_tree->{IntlRateV2Response} if (exists($response_tree->{IntlRateV2Response}));

    # Handle errors
    ### Get all errors
    my $errors = [];
    push(@$errors, $response_tree->{Error}) if (exists($response_tree->{Error}));
    if (ref $response_tree->{Package} eq 'HASH') {
        if (exists($response_tree->{Package}{Error})) {
            push(@$errors, $response_tree->{Package}{Error});
            $errors->[$#{$errors}]{PackageID} = $response_tree->{Package}{ID};
        }
    }
    elsif (ref $response_tree->{Package} eq 'ARRAY') {
        foreach my $pkg (@{ $response_tree->{Package} }) {
            if (exists($pkg->{Error})) {
                push(@$errors, $pkg->{Error});
                $errors->[$#{$errors}]{PackageID} = $pkg->{ID};
            }
        }
    }
    
    # throw an exception if there are errors
    if (@$errors > 0) {
        ouch 'USPS Error', $errors->[0]{Description}, $errors;
    } 
        
    # normalize rates for domestic and international
    my $packages = ref $response_tree->{Package} eq 'ARRAY' ?  $response_tree->{Package} : [$response_tree->{Package}];
    if ($self->domestic) {
        foreach my $package (@{$packages}) {
            my %services = ();
            foreach my $service (@{$package->{Postage}}) {
                my $service_name = $self->sanitize_service_name($service->{MailService});
                $services{$service_name} = {
                    #id          => 'USPS-Domestic-'.$service->{CLASSID},
                    #category    => $self->translate_service_name_to_category($service_name),
                    #label       => $service->{MailService},
                    postage     => $service->{Rate},
                };
            }
            $rates->{$package->{ID}} = \%services;
        }
    }
    else {
        foreach my $package (@{$packages}) {
            my %services = ();
            foreach my $service (@{$package->{Service}}) {
                my $service_name = $self->sanitize_service_name($service->{SvcDescription});
                $services{$service_name} = {
                    #id          => 'USPS-International-'.$service->{ID},
                    #category    => $self->translate_service_name_to_category($service_name),
                    #label       => $service->{SvcDescription},
                    postage     => $service->{Postage},
                };
            }
            $rates->{$package->{ID}} = \%services;
        }
    }
}

sub sanitize_service_name {
    my ($class, $name) = @_;    
    my $remove_reg = quotemeta('&lt;sup&gt;&amp;reg;&lt;/sup&gt;');
    my $remove_tm  = quotemeta('&lt;sup&gt;&amp;trade;&lt;/sup&gt;');
    my $remove_gxg = quotemeta(' (GXG)');
    $name =~ s/\*//g;
    $name =~ s/$remove_reg//gi;
    $name =~ s/$remove_tm//gi;
    $name =~ s/$remove_gxg//gi;
    $name =~ s/GXG/Global Express Guaranteed/gi;
    $name =~ s/ Mail//gi;
    $name =~ s/ International//gi;
    $name =~ s/USPS //gi;
    $name =~ s/Envelopes/Envelope/gi;
    $name =~ s/Boxes/Box/gi;
    $name =~ s/priced box/Box/gi;
    return 'USPS '.$name;
}

sub translate_service_name_to_category {
    my ($class, $name) = @_;
    if ($name =~ m/^USPS Priority.+Flat Rate/) {
        $name = 'USPS Priority Flat Rate';
    }
    elsif ($name =~ m/^USPS Express.+Flat Rate/) {
        $name = 'USPS Express Flat Rate';
    }
    elsif ($name =~ m/^USPS Express Hold For Pickup/) {
        $name = 'USPS Express';
    }
    elsif ($name =~ m/^USPS Global Express Guaranteed/) {
        $name = 'USPS Global Express Guaranteed';
    }
    elsif ($name =~ m/^USPS First-Class/) {
        $name = 'USPS First-Class';
    }
    return $name;
}

sub domestic {
    my $self = shift;
    return $self->to =~ m/^\d{5}$/ ? 1 : 0;
}

1;

