package App::CSVUtils::csv_map;

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
    name => 'csv_map',
    summary => 'Return result of Perl code for every row',
    description => <<'_',

This is like Perl's `map` performed over rows of CSV. In `$_`, your Perl code
will find the CSV row as an arrayref (or, if you specify `-H`, as a hashref).
`$main::row` is also set to the row (always as arrayref). `$main::rownum`
contains the row number (2 means the first data row). `$main::csv` is the
<pm:Text::CSV_XS> object. `$main::fields_idx` is also available for additional
information.

Your code is then free to return a string based on some operation against these
data. This utility will then print out the resulting string.

_
    add_args => {
        %App::CSVUtils::argspecopt_hash,
        %App::CSVUtils::argspec_eval,
        add_newline => {
            summary => 'Whether to make sure each string ends with newline',
            'summary.alt.bool.not' => 'Do not add newline to each output',
            schema => 'bool*',
            default => 1,
        },
    },
    tags => ['category:iterating', 'accepts-code'],

    examples => [
        {
            summary => 'Create SQL insert statements (escaping is left as an exercise for users)',
            argv => ['-He', '"INSERT INTO mytable (id,amount) VALUES ($_->{id}, $_->{amount});"', 'file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    writes_csv => 0,

    on_begin => sub {
        my $r = shift;

        # for when we are called directly as a function without wrapper to set
        # defaults etc.
        $r->{util_args}{add_newline} //= 1;
    },

    on_input_header_row => sub {
        my $r = shift;

        # we add the following keys to the stash
        $r->{code} = compile_eval_code($r->{util_args}{eval}, 'eval');

        $r->{wants_input_row_as_hashref} = 1 if $r->{util_args}{hash};
    },

    on_input_data_row => sub {
        my $r = shift;

        my $rowres = eval_code($r->{code}, $r, $r->{wants_input_row_as_hashref} ? $r->{input_row_as_hashref} : $r->{input_row}) // '';
        $rowres .= "\n" if $r->{util_args}{add_newline} && $rowres !~ /\R\z/;
        $r->{code_print}->($rowres);
    },
);

1;
# ABSTRACT:
