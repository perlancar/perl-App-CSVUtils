package App::CSVUtils::csv2td;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(gen_csv_util);

gen_csv_util(
    name => 'csv2td',
    summary => 'Return an enveloped aoaos table data from CSV data',
    description => <<'_',

Read more about "table data" in <pm:App::td>, which comes with a CLI <prog:td>
to munge table data.

_
    add_args => {
    },
    tags => ['category:converting','outputs-data-structure'],

    examples => [
        {
            summary => 'Convert to table data then use the "td" utility to grab the first 5 rows',
            src => '[[prog]] file.csv --json | td head -n5',
            src_plang => 'bash',
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    on_input_header_row => sub {
        my $r = shift;

        $r->{result} = [200, "OK", [], {'table.fields' => $r->{input_fields}}];
    },

    on_input_data_row => sub {
        my $r = shift;

        push @{ $r->{result}[2] }, $r->{input_row};
    },

    writes_csv => 0,
);

1;
# ABSTRACT:
