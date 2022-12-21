package App::CSVUtils::csv_split;

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
    name => 'csv_split',
    summary => 'Split CSV file into several files',
    description => <<'_',

Will output split files xaa, xab, and so on. Each split file will contain a
maximum of `lines` rows (options to limit split files' size based on number of
characters and bytes will be added). Each split file will also contain CSV
header.

Warning: by default, existing split files xaa, xab, and so on will be
overwritten.

Interface is loosely based on the `split` Unix utility.

_
    add_args => {
        lines => {
            schema => 'posint*',
            default => 1000,
            cmdline_aliases => {l=>{}},
        },
        # XXX --bytes (-b)
        # XXX --line-bytes (-C)
        # XXX -d (numeric suffix)
        # --suffix-length (-a)
        # --number, -n (chunks)
    },
    examples => [
        {
            summary => 'Split CSV files to xaa, xab, ... where each split file gets 1000 rows',
            argv => ['file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    writes_multiple_csv => 1,

    before_read_input => sub {
        my $r = shift;

        $r->{output_filenames} = ['xaa'];
        $r->{output_num_of_files} = '?';
    },

    on_input_data_row => sub {
        my $r = shift;

        # time to switch to another file?
        if ($r->{input_data_rownum} > 1 && ($r->{input_data_rownum}+1) % $r->{util_args}{lines} == 0) {
            $r->{wants_switch_to_next_output_file}++;
            my $next_filename = $r->{output_filenames}[-1];
            $next_filename++;
            push @{ $r->{output_filenames} }, $next_filename;
        }

        $r->{code_print_row}->($r->{input_row});
    },
);

1;
# ABSTRACT:
