package App::CSVUtils::csv_list_field_names;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(gen_csv_util);

gen_csv_util(
    name => 'csv_list_field_names',
    summary => 'List field names of CSV file',
    description => <<'MARKDOWN',

MARKDOWN

    add_args => {
    },

    examples => [
        {
            summary => 'List field names of a CSV as a text table of name and position',
            argv => ['file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'List field names of a CSV as tab-separated lines, sort by name',
            src => '[[prog]] file.csv | sort',
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    writes_csv => 0,

    tags => ['category:information'],

    on_input_header_row => sub {
        my $r = shift;

        $r->{result} = [
            200,
            "OK", [
                map { {name=>$_, index=>$r->{input_fields_idx}{$_}+1} }
                sort keys %{$r->{input_fields_idx}}
            ],
            {'table.fields'=>['name','index']},
        ];
        $r->{wants_skip_files}++;
    }
);

1;
# ABSTRACT:
