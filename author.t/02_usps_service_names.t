use strict;
use Test::More;
use lib '../lib';
use Box::Calc;
use 5.010;

my $user_id  = $ENV{USPS_USERID};
my $password = $ENV{USPS_PASSWORD};

if (!$user_id || !$password) {
    plan skip_all => 'Missing USPS_USERID or USPS_PASSWORD';
}


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
    user_id     => $user_id,
    password    => $password,
    from        => 53716,
    to          => 90210,
);
my $rates = $rate->request_rates($calc->boxes)->recv;


my %services = %{$rates->{$calc->get_box(0)->id}};


$rate = USPS::RateRequest->new(
    user_id     => $user_id,
    password    => $password,
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

