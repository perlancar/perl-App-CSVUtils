package App::CSVUtils::csv_select_fields;

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
    name => 'csv_select_fields',
    summary => 'Select (only output) field(s) using a combination of excludes/includes, including by regex',
    add_args => {
        %App::CSVUtils::argspecsopt_field_selection,
        %App::CSVUtils::argspecsopt_show_selected_fields,
    },
    tags => ['category:filtering'],

    examples => [
        {
            summary => 'Select a single field from CSV',
            argv => ['file.csv', '-f', 'f1'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Select several fields from CSV',
            argv => ['file.csv', '-f', 'f1', '-f', 'f2', '-f', 'f3'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Select fields matching regex from CSV',
            argv => ['file.csv', '--include-field-pat', '/^extra_/'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Select all fields except specified from CSV',
            argv => ['file.csv', '-a', '-f', 'f1', '-f', 'f2'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Only show what fields would be included, then exit',
            argv => ['file.csv', '--include-field-pat', '/^extra_/', '--show-selected-fields'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    on_input_data_row => sub {
        my $r = shift;

        # we add the following keys to the stash
        unless ($r->{selected_fields_idx_array_sorted}) {
            my $res = App::CSVUtils::_select_fields($r->{input_fields}, $r->{input_fields_idx}, $r->{util_args});
            die $res unless $res->[0] == 100;
            my $selected_fields = $res->[2][0];
            my $selected_fields_idx_array = $res->[2][1];
            die [412, "At least one field must be selected"]
                unless @$selected_fields;
            $r->{selected_fields_idx_array_sorted} = [sort { $b <=> $a } @$selected_fields_idx_array];

            # set ouput fields
            $r->{output_fields} = [];
            for (@{ $r->{selected_fields_idx_array_sorted} }) {
                push @{ $r->{output_fields} }, $r->{input_fields}[$_];
            }

            if ($r->{util_args}{show_selected_fields}) {
                $r->{wants_skip_files}++;
                $r->{result} = [200, "OK", $selected_fields];
                return;
            }
        }

        my $row = [];
        for (@{ $r->{selected_fields_idx_array_sorted} }) {
            push @$row, $r->{input_row}[$_];
        }

        $r->{code_print_row}->($row);
    },
);

1;
# ABSTRACT:
