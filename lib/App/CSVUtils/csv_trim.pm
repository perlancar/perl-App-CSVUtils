package App::CSVUtils::csv_trim;

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
    name => 'csv_trim',
    summary => 'Trim (remove leading & trailing whitespace) values and/or fields in CSV',
    description => <<'_',

Whitespace includes space, tab, and newline.

_
    add_args => {
        trim_fields => {
            schema => 'bool*',
            summary => 'Whether also to trim the field names',
        },
        trim_values => {
            schema => 'bool*',
            summary => 'Whether to trim the values in the data rows',
            default => 1,
        },
    },
    examples => [
        {
            summary => 'Trim values in a CSV',
            argv => ['FILE.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
    links => [
        {url=>'prog:csv-ltrim'},
        {url=>'prog:csv-rtrim'},
    ],

    tags => ['category:munging', 'modifies-values'],

    on_begin => sub {
        my $r = shift;

        # XXX schema
        $r->{util_args}{trim_values} //= 1;
    },

    on_input_header_row => sub {
        my $r = shift;

        $r->{output_fields} = [];
        $r->{output_fields_idx} = {};

        my $i = -1;
        for my $f (@{ $r->{input_fields} }) {
            if ($r->{util_args}{trim_fields}) {
                my $f0 = $f;
                $i++;
                $f =~ s/\A\s+//s;
                $f =~ s/\s+\z//s;
                die [500, "Can't trim field '$f0' to '$f': will cause duplicate fields"]
                    if exists $r->{output_fields_idx}{$f};
            }
            push @{$r->{output_fields}}, $f;
            $r->{output_fields_idx}{$f} = $i;
        }
    },

    on_input_data_row => sub {
        my $r = shift;

        if ($r->{util_args}{trim_values}) {
            for my $f (@{$r->{input_row}}) {
                $f =~ s/\A\s+//s;
                $f =~ s/\s+\z//s;
            }
        }

        $r->{code_print_row}->($r->{input_row});
    },
);

1;
# ABSTRACT:
