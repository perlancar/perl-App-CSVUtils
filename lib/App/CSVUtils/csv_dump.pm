package App::CSVUtils::csv_dump;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(gen_csv_util);

gen_csv_util(
    name => 'csv_dump',
    summary => 'Dump CSV as data structure (array of array/hash)',

    on_input_header_row => sub {
        my $r = shift;
        $r->{rows} //= [];
        push @{ $r->{rows} }, $r->{row};
    },

    on_input_data_row => sub {
        my $r = shift;
        push @{ $r->{rows} }, $r->{row};
    },

    on_output => sub {
        my $r = shift;
        $r->{result} = [200, "OK", $r->{rows}];
    },
);

1;
# ABSTRACT:
