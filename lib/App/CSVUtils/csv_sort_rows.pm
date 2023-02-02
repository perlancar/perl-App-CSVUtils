package App::CSVUtils::csv_sort_rows;

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

sub on_input_header_row {
    my $r = shift;
    $r->{wants_input_row_as_hashref}++ if $r->{util_args}{hash};
}

sub on_input_data_row {
    my $r = shift;

    # keys we add to the stash
    $r->{input_rows} //= [];
    if ($r->{wants_input_row_as_hashref}) {
        $r->{input_rows_as_hashref} //= [];
    }

    push @{ $r->{input_rows} }, $r->{input_row};
    if ($r->{wants_input_row_as_hashref}) {
        push @{ $r->{input_rows_as_hashref} }, $r->{input_row_as_hashref};
    }
}

sub after_close_input_files {
    my $r = shift;

    # we do the actual sorting here after collecting all the rows

    # whether we should compute keys
    my @keys;
    if ($r->{util_args}{key}) {
        my $code_gen_key = compile_eval_code($r->{util_args}{key}, 'key');
        for my $row (@{ $r->{util_args}{hash} ? $r->{input_rows_as_hashref} : $r->{input_rows} }) {
            local $_ = $row;
            push @keys, $code_gen_key->($row);
        }
    }

    my $sorted_rows;
    if ($r->{util_args}{by_code} || $r->{util_args}{by_sortsub}) {

        my $code0;
        if ($r->{util_args}{by_code}) {
            $code0 = compile_eval_code($r->{util_args}{by_code}, 'by_code');
        } elsif (defined $r->{util_args}{by_sortsub}) {
            require Sort::Sub;
            $code0 = Sort::Sub::get_sorter(
                $r->{util_args}{by_sortsub}, $r->{util_args}{sortsub_args});
        }

        my $sort_indices;
        my $code;
        if (@keys) {
            # compare two sort keys ($a & $b) are indices
            $sort_indices++;
            $code = sub {
                local $main::a = $keys[$a];
                local $main::b = $keys[$b];
                #log_trace "a=<$main::a> vs b=<$main::b>";
                $code0->($main::a, $main::b);
            };
        } elsif ($r->{util_args}{hash}) {
            $sort_indices++;
            $code = sub {
                local $main::a = $r->{input_rows_as_hashref}[$a];
                local $main::b = $r->{input_rows_as_hashref}[$b];
                #log_trace "a=<%s> vs b=<%s>", $main::a, $main::b;
                $code0->($main::a, $main::b);
            };
        } else {
            $code = $code0;
        }

        if ($sort_indices) {
            my @sorted_indices = sort { local $main::a=$a; local $main::b=$b; $code->($main::a,$main::b) } 0..$#{$r->{input_rows}};
            $sorted_rows = [map {$r->{input_rows}[$_]} @sorted_indices];
        } else {
            $sorted_rows = [sort { local $main::a=$a; local $main::b=$b; $code->($main::a,$main::b) } @{$r->{input_rows}}];
        }

    } elsif ($r->{util_args}{by_fields}) {

        my @fields;
        my $code_str = "";
        for my $field_spec (@{ $r->{util_args}{by_fields} }) {
            my ($prefix, $field) = $field_spec =~ /\A([+~-]?)(.+)/;
            my $field_idx = $r->{input_fields_idx}{$field};
            die [400, "Unknown field '$field' (known fields include: ".
                 join(", ", map { "'$_'" } sort {$r->{input_fields_idx}{$a} <=> $r->{input_fields_idx}{$b}}
                      keys %{$r->{input_fields_idx}}).")"] unless defined $field_idx;
            $prefix //= "";
            if ($prefix eq '+') {
                $code_str .= ($code_str ? " || " : "") .
                    "(\$a->[$field_idx] <=> \$b->[$field_idx])";
            } elsif ($prefix eq '-') {
                $code_str .= ($code_str ? " || " : "") .
                    "(\$b->[$field_idx] <=> \$a->[$field_idx])";
            } elsif ($prefix eq '') {
                if ($r->{util_args}{ci}) {
                    $code_str .= ($code_str ? " || " : "") .
                        "(lc(\$a->[$field_idx]) cmp lc(\$b->[$field_idx]))";
                } else {
                    $code_str .= ($code_str ? " || " : "") .
                        "(\$a->[$field_idx] cmp \$b->[$field_idx])";
                }
            } elsif ($prefix eq '~') {
                if ($r->{util_args}{ci}) {
                    $code_str .= ($code_str ? " || " : "") .
                        "(lc(\$b->[$field_idx]) cmp lc(\$a->[$field_idx]))";
                } else {
                    $code_str .= ($code_str ? " || " : "") .
                        "(\$b->[$field_idx] cmp \$a->[$field_idx])";
                }
            }
        }
        my $code = compile_eval_code($code_str, 'from sort_by_fields');
        $sorted_rows = [sort { local $main::a = $a; local $main::b = $b; $code->($main::a, $main::b) } @{$r->{input_rows}}];

    } else {

        die [400, "Please specify by_fields or by_sortsub or by_code"];

    }

    if ($main::_CSV_SORTED_ROWS) {
        require Data::Cmp;
        #use DD; dd $r->{input_rows}; print "\n"; dd $sorted_rows;
        if (Data::Cmp::cmp_data($r->{input_rows}, $sorted_rows)) {
            # not sorted
            $r->{result} = [400, "NOT sorted", $r->{util_args}{quiet} ? undef : "Rows are NOT sorted"];
        } else {
            # sorted
            $r->{result} = [200, "Sorted", $r->{util_args}{quiet} ? undef : "Rows are sorted"];
        }
    } else {
        for my $row (@$sorted_rows) {
            $r->{code_print_row}->($row);
        }
    }
}

gen_csv_util(
    name => 'csv_sort_rows',
    summary => 'Sort CSV rows',
    description => <<'_',

This utility sorts the rows in the CSV. Example input CSV:

    name,age
    Andy,20
    Dennis,15
    Ben,30
    Jerry,30

Example output CSV (using `--by-field +age` which means by age numerically and
ascending):

    name,age
    Dennis,15
    Andy,20
    Ben,30
    Jerry,30

Example output CSV (using `--by-field -age`, which means by age numerically and
descending):

    name,age
    Ben,30
    Jerry,30
    Andy,20
    Dennis,15

Example output CSV (using `--by-field name`, which means by name ascibetically
and ascending):

    name,age
    Andy,20
    Ben,30
    Dennis,15
    Jerry,30

Example output CSV (using `--by-field ~name`, which means by name ascibetically
and descending):

    name,age
    Jerry,30
    Dennis,15
    Ben,30
    Andy,20

Example output CSV (using `--by-field +age --by-field ~name`):

    name,age
    Dennis,15
    Andy,20
    Jerry,30
    Ben,30

You can also reverse the sort order (`-r`) or sort case-insensitively (`-i`).

For more flexibility, instead of `--by-field` you can use `--by-code`:

Example output `--by-code '$a->[1] <=> $b->[1] || $b->[0] cmp $a->[0]'` (which
is equivalent to `--by-field +age --by-field ~name`):

    name,age
    Dennis,15
    Andy,20
    Jerry,30
    Ben,30

If you use `--hash`, your code will receive the rows to be compared as hashref,
e.g. `--hash --by-code '$a->{age} <=> $b->{age} || $b->{name} cmp $a->{name}'.

A third alternative is to sort using <pm:Sort::Sub> routines. Example output
(using `--by-sortsub 'by_length<r>' --key '$_->[0]'`, which is to say to sort by
descending length of name):

    name,age
    Dennis,15
    Jerry,30
    Andy,20
    Ben,30

_

    add_args => {
        %App::CSVUtils::argspecopt_hash,
        %App::CSVUtils::argspecs_sort_rows,
    },
    add_args_rels => {
        req_one => ['by_fields', 'by_code', 'by_sortsub'],
    },

    on_input_header_row => \&App::CSVUtils::csv_sort_rows::on_input_header_row,

    on_input_data_row => \&App::CSVUtils::csv_sort_rows::on_input_data_row,

    after_close_input_files => \&App::CSVUtils::csv_sort_rows::after_close_input_files,

);

1;
# ABSTRACT:

=for Pod::Coverage ^(on|after|before)_.+$
