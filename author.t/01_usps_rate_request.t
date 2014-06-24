use strict;
use Test::More;
use lib '../lib';
use BCS::Perl;
use BCS;
use Box::Calc;

use_ok 'USPS::RateRequest';

my $calc = Box::Calc->new();
$calc->add_box_type({
    x => 12,
    y => 12,
    z => 5.75,
    weight => 10,
    name => 'A',
});
$calc->add_item(2,
    x => 8,
    y => 8,
    z => 5.75,
    name => 'small pumpkin',
    weight => 66,
);
$calc->pack_items;

my $rate = USPS::RateRequest->new(
    user_id     => BCS->config->get('usps/user_id'),
    password    => BCS->config->get('usps/password'),
    from        => 53716,
    to          => 90210,
);


isa_ok $rate, 'USPS::RateRequest';
my $rates = $rate->request_rates($calc->boxes)->recv;
is scalar(keys %$rates), 2, 'got back 2 packages worth of rates from California';
cmp_ok $rates->{$calc->get_box(0)->id}{'USPS Priority'}{postage}, '>', 0, 'got a rate from California';

use Data::Dumper;
say Dumper $rates;

$rate = USPS::RateRequest->new(
    user_id     => BCS->config->get('usps/user_id'),
    password    => BCS->config->get('usps/password'),
    from        => 53716,
    to          => 'Australia',
);

isa_ok $rate, 'USPS::RateRequest';
$rates = $rate->request_rates($calc->boxes)->recv;
is scalar(keys %$rates), 2, 'got back 2 packages worth of rates from Australia';
cmp_ok $rates->{$calc->get_box(0)->id}{'USPS Priority'}{postage}, '>', 0, 'got a rate from Australia';


say Dumper $rates;



done_testing();

