package App::CSVUtils::csv_sort_fields;

use 5.010001;
use strict;
use warnings;
use Log::ger;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(
                        gen_csv_util
                        compile_eval_code
                );

gen_csv_util(
    name => 'csv_sort_fields',
    summary => 'Sort CSV fields',
    description => <<'_',

This utility sorts the order of fields in the CSV. Example input CSV:

    b,c,a
    1,2,3
    4,5,6

Example output CSV:

    a,b,c
    3,1,2
    6,4,5

You can also reverse the sort order (`-r`), sort case-insensitively (`-i`), or
provides the ordering example, e.g. `--by-examples-json '["a","c","b"]'`, or use
`--by-code` or `--by-sortsub`.

_

    add_args => {
        %App::CSVUtils::argspecs_sort_fields,
    },
    add_args_rels => {
        choose_one => ['by_examples', 'by_code', 'by_sortsub'],
    },

    on_input_header_row => sub {
        my $r = shift;

        my $code;
        my $code_gets_field_with_pos;
        if ($r->{util_args}{by_code}) {
            $code_gets_field_with_pos++;
            $code = compile_eval_code($r->{util_args}{by_code}, 'by_code');
        } elsif (defined $r->{util_args}{by_sortsub}) {
            require Sort::Sub;
            $code = Sort::Sub::get_sorter(
                $r->{util_args}{by_sortsub}, $r->{util_args}{sortsub_args});
        } elsif (my $eg = $r->{util_args}{by_examples}) {
            require Sort::ByExample;
            $code = Sort::ByExample->cmp($eg);
        } else {
            $code = sub { $_[0] cmp $_[1] };
        }

        my @sorted_indices = sort {
            my $field_a = $r->{util_args}{ci} ? lc($r->{input_fields}[$a]) : $r->{input_fields}[$a];
            my $field_b = $r->{util_args}{ci} ? lc($r->{input_fields}[$b]) : $r->{input_fields}[$b];
            local $main::a = $code_gets_field_with_pos ? [$field_a, $a] : $field_a;
            local $main::b = $code_gets_field_with_pos ? [$field_b, $b] : $field_b;
            ($r->{util_args}{reverse} ? -1:1) * $code->($main::a, $main::b);
        } 0..$#{$r->{input_fields}};

        $r->{output_fields} = [map {$r->{input_fields}[$_]} @sorted_indices];
        $r->{output_fields_idx_array} = \@sorted_indices; # this is a key we add to stash
    },

    on_input_data_row => sub {
        my $r = shift;

        my $row = [];
        for my $j (@{ $r->{output_fields_idx_array} }) {
            push @$row, $r->{input_row}[$j];
        }
        $r->{code_printrow}->($row);
    },

);

1;
# ABSTRACT:
