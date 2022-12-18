package App::CSVUtils::csv_gen;

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
                );

gen_csv_util(
    name => 'csv_gen',
    summary => 'Generate CSV data using Perl code',

    add_args => {
        fields => $App::CSVUtils::argspec_fields{fields},
        eval_fields => {
            summary => 'Code to generate list of fields',
            schema => 'str*',
            description => <<'_',

This is an alternative to supplying a static list of fields via `fields` option.

Code is expected to return the list of fields as an arrayref.

_
        },
        hash => {
            summary => 'Expect the code that generates row to return hashref instead of arrayref',
            schema => 'true*',
            cmdline_aliases => {H=>{}},
        },
        eval => {
            summary => 'Code to generate row',
            schema => 'str*',
            description => <<'_',

Code will be compiled in the `main` package.

Code is expected to return the row data. If `hash` option is in effect, code
should return a hashref. Otherwise, code should return an arrayref.

_
        },
    },

    add_args_rels => {
        req_one => ['fields', 'eval_fields'],
    },

    accepts_csv => 0,

    outputs_csv => 1,

    on_output_header_row => sub {
        my $r = shift;

        my $fields;
        if ($r->{util_args}{eval_fields}) {
            my $code = compile_eval_code($r->{util_args}{eval_fields}, 'eval_fields');
            local $main::r = $r;
            $fields = $code->();
            die [500, "Code in eval_fields did not return list of fields as arranref"]
                unless ref $fields eq 'ArRAY';
        }
        $r->{fields} = $fields;
        for my $j (0 .. $#{ $r->{fields} }) {
            $r->{fields_idx}{ $r->{fields}[$j] } = $j;
        }
    },

    on_output_data_rows => {
    },

);

1;
# ABSTRACT:
