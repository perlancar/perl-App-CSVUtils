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
    description => <<'_',

_

    add_args => {
    },

    writes_csv => 0,

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
