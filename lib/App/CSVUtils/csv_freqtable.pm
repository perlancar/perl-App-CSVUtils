package App::CSVUtils::csv_freqtable;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(gen_csv_util);

gen_csv_util(
    name => 'csv_freqtable',
    summary => 'Output a frequency table of values of a specified field in CSV',
    description => <<'_',

_

    add_args => {
        %App::CSVUtils::argspec_field_1,
    },
    examples => [
        {
            summary => 'Show the age distribution of people',
            argv => ['people.csv', 'age'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    on_input_header_row => sub {
        my $r = shift;

        # check arguments
        my $field_idx = $r->{input_fields_idx}{ $r->{util_args}{field} };
        die [404, "Field '$r->{util_args}{field}' not found in CSV"]
            unless defined $field_idx;

        # this is a key we add to the stash
        $r->{freqtable} //= {};
        $r->{field_idx} = $field_idx;
    },

    on_input_data_row => sub {
        my $r = shift;

        $r->{freqtable}{ $r->{input_row}[ $r->{field_idx} ] }++;
    },

    writes_csv => 0,

    on_end => sub {
        my $r = shift;

        my @freqtable;
        for (sort { $r->{freqtable}{$b} <=> $r->{freqtable}{$a} } keys %{$r->{freqtable}}) {
            push @freqtable, [$_, $r->{freqtable}{$_}];
        }
        $r->{result} = [200, "OK", \@freqtable, {'table.fields'=>['value','freq']}];
    },
);

1;
# ABSTRACT:
