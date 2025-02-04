package App::CSVUtils::csv_check_rows;

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
    name => 'csv_check_rows',
    summary => 'Check CSV rows',
    description => <<'MARKDOWN',

This utility performs the following checks:

For header row:

For data rows:

- There are the same number of values as the number of fields (no missing
  values, no extraneous values)

For each failed check, an error message will be printed to stderr. And if there
is any error, the exit code will be non-zero. If there is no error, the utility
outputs nothing and exits with code zero.

There will be options to add some additional checks in the future.

Note that parsing errors, e.g. missing closing quotes on values, are currently
handled by <pm:Text::CSV_XS>.

MARKDOWN
    add_args => {
    },
    tags => ['category:checking'],

    examples => [
        {
            summary => 'Check CSV rows',
            argv => ['file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    writes_csv => 0,

    on_input_header_row => sub {
        my $r = shift;

        $r->{wants_fill_rows} = 0;

        # we add the following key(s) to the stash
        $r->{num_errors} = 0;
    },

    on_input_data_row => sub {
        my $r = shift;

        if (@{ $r->{input_row} } != @{ $r->{input_fields} }) {
            warn "csv-check-rows: Row #$r->{input_rownum}: There are too few/many values (".scalar(@{ $r->{input_row} }).", should be ".scalar(@{ $r->{input_fields} }).")\n";
            $r->{num_errors}++;
        }
    },

    after_close_input_files => sub {
        my $r = shift;

        $r->{result} = $r->{num_errors} ? [400, "Some rows have error"] : [200, "All rows ok"];
    },
);

1;
# ABSTRACT:
