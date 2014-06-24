use strict;
use Test::More;
use lib '../lib';
use BCS::Perl;
use BCS;
use Box::Calc;

use_ok 'USPS::RateRequest';

my $calc = Box::Calc->new();
$calc->add_box_type({
    x => 1,
    y => 1,
    z => 1,
    weight => 10,
    name => 'A',
});
$calc->add_item(1,
    x => 1,
    y => 1,
    z => 1,
    name => 'cube',
    weight => 1,
);
$calc->pack_items;

my $rate = USPS::RateRequest->new(
    user_id     => BCS->config->get('usps/user_id'),
    password    => BCS->config->get('usps/password'),
    from        => 53716,
    to          => 90210,
);
my $rates = $rate->request_rates($calc->boxes)->recv;


my %services = %{$rates->{$calc->get_box(0)->id}};


$rate = USPS::RateRequest->new(
    user_id     => BCS->config->get('usps/user_id'),
    password    => BCS->config->get('usps/password'),
    from        => 53716,
    to          => 'Australia',
);
$rates = $rate->request_rates($calc->boxes)->recv;

%services = (%services, %{$rates->{$calc->get_box(0)->id}});

my @names = keys %services;

foreach my $name (sort @names) {
    note $name;
}

done_testing();

