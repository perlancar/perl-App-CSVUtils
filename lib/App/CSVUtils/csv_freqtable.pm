package App::CSVUtils::csv_freqtable;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(
                        gen_csv_util
                        compile_eval_code
                        eval_code
                );

gen_csv_util(
    name => 'csv_freqtable',
    summary => 'Output a frequency table of values of a specified field in CSV',
    description => <<'_',

_

    add_args => {
        %App::CSVUtils::argspecopt_field_1,
        ignore_case => {
            summary => 'Ignore case',
            schema => 'true*',
            cmdline_aliases => {i=>{}},
        },
        key => {
            summary => 'Generate computed field with this Perl code',
            description => <<'_',

If specified, then will compute field using Perl code.

The code will receive the row (arrayref, or if -H is specified, hashref) as the
argument. It should return the computed field (str).

_
            schema => $App::CSVUtils::sch_req_str_or_code,
            cmdline_aliases => {k=>{}},
        },
        %App::CSVUtils::argspecopt_hash,
    },
    add_args_rels => {
        'req_one&' => [ ['field', 'key'] ],
    },
    tags => ['category:summarizing', 'outputs-data-structure', 'accepts-code'],

    examples => [
        {
            summary => 'Show the age distribution of people',
            argv => ['people.csv', 'age'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Show the frequency of wins by a user, ignore case differences in user',
            argv => ['winner.csv', 'user', '-i'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Show the frequency of events by period (YYYY-MM)',
            argv => ['events.csv', '-H', '--key', 'sprintf("%04d-%02d", $_->{year}, $_->{month})'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    on_input_header_row => sub {
        my $r = shift;

        # check arguments
        my $field_idx;
        if (defined $r->{util_args}{field}) {
            $field_idx = $r->{input_fields_idx}{ $r->{util_args}{field} };
            die [404, "Field '$r->{util_args}{field}' not found in CSV"]
                unless defined $field_idx;
        }

        $r->{wants_input_row_as_hashref} = 1 if $r->{util_args}{hash};

        # this is a key we add to the stash
        $r->{freqtable} //= {};
        $r->{field_idx} = $field_idx;
        $r->{code} = undef;
    },

    on_input_data_row => sub {
        my $r = shift;

        my $field_val;
        if ($r->{util_args}{key}) {
            unless ($r->{code}) {
                $r->{code} = compile_eval_code($r->{util_args}{key}, 'key');
            }
            $field_val = eval_code($r->{code}, $r, $r->{wants_input_row_as_hashref} ? $r->{input_row_as_hashref} : $r->{input_row}) // '';
        } else {
            $field_val = $r->{input_row}[ $r->{field_idx} ];
        }

        if ($r->{util_args}{ignore_case}) {
            $field_val = lc $field_val;
        }

        $r->{freqtable}{$field_val}++;
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
