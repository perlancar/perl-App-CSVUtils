package App::CSVUtils::csv_each_row;

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
    name => 'csv_each_row',
    summary => 'Run Perl code for every data row',
    description => <<'_',

This is like <prog:csv-map>, except result of code is not printed.

_
    add_args => {
        %App::CSVUtils::argspecopt_hash,
        %App::CSVUtils::argspec_eval,
    },
    tags => ['category:iterating', 'accepts-code'],
    examples => [
        {
            summary => 'Delete user data',
            argv => ['-He', '"unlink qq(/home/data/$_->{username}.dat)"', 'users.csv'],
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

        eval_code($r->{code}, $r, $r->{wants_input_row_as_hashref} ? $r->{input_row_as_hashref} : $r->{input_row});
    },
);

1;
# ABSTRACT:
