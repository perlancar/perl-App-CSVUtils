package App::CSVUtils::csv_munge_row;

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
    name => 'csv_munge_row',
    summary => '',
    description => <<'_',

Perl code (-e) will be called for each row (excluding the header row) and `$_`
will contain the row (arrayref, or hashref if `-H` is specified). The Perl code
is expected to modify it.

Aside from `$_`, `$main::row` will contain the current row array.
`$main::rownum` contains the row number (2 means the first data row).
`$main::csv` is the <pm:Text::CSV_XS> object. `$main::field_idxs` is also
available for additional information.

The modified `$_` will be rendered back to CSV row.

You cannot add new fields using this utility. To do so, use
<prog:csv-add-fields>. You also cannot delete fields (they just become empty
string if you delete the field in the eval code). To delete fields, use
<prog:csv-delete-fields>.

Note that you can also munge a single field using <prog:csv-munge-field>.

_
    add_args => {
        %App::CSVUtils::argspec_eval_1,
        %App::CSVUtils::argspecopt_hash,
    },
    examples => [
        {
            summary => 'Modify two fields in a CSV',
            argv => ['-He', '$_->{field1} *= 2; $_->{field2} =~ s/foo/bar/', 'file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    on_input_header_row => sub {
        my $r = shift;

        # we add the following keys to the stash
        $r->{code} = compile_eval_code($r->{util_args}{eval}, 'eval');

        $r->{wants_input_row_as_hashref} = 1 if $r->{util_args}{hash};
    },

    on_input_data_row => sub {
        my $r = shift;

        {
            local $_ = $r->{wants_input_row_as_hashref} ? $r->{input_row_as_hashref} : $r->{input_row};
            local $main::row = $r->{input_row};
            local $main::rownum = $r->{input_rownum};
            local $main::csv = $r->{input_parser};
            local $main::field_idxs = $r->{input_fields_idx};
            eval { $r->{code}->($_) };
            die [500, "Error while munging row #$r->{input_rownum}: $@\n"] if $@;
            # convert back hashref row to arrayref
            my $newrow;
            if ($r->{util_args}{hash}) {
                $newrow = [('') x @{ $r->{input_fields} }];
                for my $field (keys %$_) {
                    next unless exists $r->{input_fields_idx}{$field}; # ignore created fields
                    $newrow->[$r->{input_fields_idx}{$field}] = $_->{$field};
                }
            } else {
                $newrow = $_;
            }
            $r->{code_printrow}->($newrow);
        }
    },
);

1;
# ABSTRACT: