package App::CSVUtils::csv_intrange;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(
                        gen_csv_util
                );

gen_csv_util(
    name => 'csv_intrange',
    summary => 'Output a summary row which are range notation of numbers',
    description => <<'_',

You can use this to check whether integer values in a column form a contiguous
range.

Non-numbers will be assumed to be 0.

Example:

    # products.csv
    name,sku_number
    foo,1
    bar,2
    baz,3
    qux,4

    % csv-intrange products.csv
    name,sku_number
    0,1..4

    # products2.csv
    name,sku_number
    foo,1
    bar,2
    baz,3
    qux,4
    quux,6
    corge,6

    % csv-sum products2 --with-data-row
    name,sku_number
    foo,1
    bar,2
    baz,3
    qux,4
    quux,6
    corge,6
    0,"1..4,6"

_
    add_args => {
        %App::CSVUtils::argspecopt_with_data_rows,
        sort => {
            summary => 'Sort the values first',
            schema => 'true*',
            description => <<'_',

Sort is done numerically, in ascending order.

If you want only certain fields sorted, you can use <prog:csv-sort-rows> first
and pipe the result.

_
        },
    },

    on_input_header_row => sub {
        my $r = shift;

        # we add this key to the stash
        $r->{field_values} = [map {[]} @{$r->{input_fields}}];

        # because input_* will be cleared by the time of after_read_input,
        # we save and set it now
        $r->{output_fields} = $r->{input_fields};
    },

    on_input_data_row => sub {
        my $r = shift;

        for my $j (0 .. $#{ $r->{input_fields} }) {
            no warnings 'numeric', 'uninitialized';
            push @{ $r->{field_values}[$j] }, $r->{input_row}[$j]+0;
        }
        $r->{code_print_row}->($r->{input_row}) if $r->{util_args}{with_data_rows};
    },

    after_read_input => sub {
        require Number::Util::Range;

        my $r = shift;

        if ($r->{util_args}{sort}) {
            for my $j (0 .. $#{ $r->{output_fields} }) {
                $r->{field_values}[$j] = [ sort { $a <=> $b } @{ $r->{field_values}[$j] } ];
            }
        }

        my @ranges;
        for my $j (0 .. $#{ $r->{output_fields} }) {
            push @ranges, join(",", @{ Number::Util::Range::convert_number_sequence_to_range(array => $r->{field_values}[$j], ignore_duplicates=>1) });
        }

        $r->{code_print_row}->(\@ranges);
    },
);

1;
# ABSTRACT:

=head1 SEE ALSO

L<Number::Util::Range>
