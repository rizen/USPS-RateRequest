use strict;
use Test::More;
use lib '../lib';
use Box::Calc;

use_ok 'USPS::RateRequest';

##The goal of this test is to exercise the sanitize_service_names class method.
##Enter in pairs of text, input and expected output.

my @vectors = (
    'Priority Mail&lt;sup&gt;&amp;reg;&lt;/sup&gt;', 'USPS Priority',
    'Priority Mail&lt;sup&gt;&amp;reg;&lt;/sup&gt; International', 'USPS Priority',
    'Priority Mail&lt;sup&gt;&#174;&lt;/sup&gt;', 'USPS Priority',
    'First-Class Mail', 'USPS First-Class',
    'Priority Mail&lt;sup&gt;&#174;&lt;/sup&gt; Large Flat Rate Box', 'USPS Priority Large Flat Rate Box',
    'Priority Mail&lt;sup&gt;&#174;&lt;/sup&gt; Medium Flat Rate Box', 'USPS Priority Medium Flat Rate Box',
    'Priority Mail&lt;sup&gt;&#174;&lt;/sup&gt; Small Flat Rate Box', 'USPS Priority Small Flat Rate Box',
    'Priority Mail&lt;sup&gt;&#174;&lt;/sup&gt; Flat Rate Envelope', 'USPS Priority Flat Rate Envelope',
    'Priority Mail&lt;sup&gt;&#174;&lt;/sup&gt; Legal Flat Rate Envelope', 'USPS Priority Legal Flat Rate Envelope',
    'Priority Mail&lt;sup&gt;&#174;&lt;/sup&gt; Padded Flat Rate Envelope', 'USPS Priority Padded Flat Rate Envelope',
    'Priority Mail&lt;sup&gt;&#174;&lt;/sup&gt; Gift Card Flat Rate Envelope', 'USPS Priority Gift Card Flat Rate Envelope',
    'Standard Post&lt;sup&gt;&#174;&lt;/sup&gt;', 'USPS Standard Post',
);
    #'', '',

if (scalar @vectors %2 == 1) {
    ##Odd number of array elements, die and complain.
    BAIL_OUT('Odd number of elements in \@vectors, aborting');
}

while (my ($input, $output) = splice @vectors, 0, 2) {
    is USPS::RateRequest->sanitize_service_name($input), $output, "Testing $input";
}

done_testing();

