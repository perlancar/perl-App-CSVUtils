package App::CSVUtils::csv_lookup_fields;

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
    name => 'csv_lookup_fields',
    summary => 'Fill fields of a CSV file from another',
    description => <<'_',

Example input:

    # report.csv
    client_id,followup_staff,followup_note,client_email,client_phone
    101,Jerry,not renewing,
    299,Jerry,still thinking over,
    734,Elaine,renewing,

    # clients.csv
    id,name,email,phone
    101,Andy,andy@example.com,555-2983
    102,Bob,bob@acme.example.com,555-2523
    299,Cindy,cindy@example.com,555-7892
    400,Derek,derek@example.com,555-9018
    701,Edward,edward@example.com,555-5833
    734,Felipe,felipe@example.com,555-9067

To fill up the `client_email` and `client_phone` fields of `report.csv` from
`clients.csv`, we can use:

    % csv-lookup-fields report.csv clients.csv --lookup-fields client_id:id --fill-fields client_email:email,client_phone:phone

The result will be:

    client_id,followup_staff,followup_note,client_email,client_phone
    101,Jerry,not renewing,andy@example.com,555-2983
    299,Jerry,still thinking over,cindy@example.com,555-7892
    734,Elaine,renewing,felipe@example.com,555-9067

_
    add_args => {
        ignore_case => {
            schema => 'bool*',
            cmdline_aliases => {ci=>{}, i=>{}},
        },
        fill_fields => {
            schema => ['str*'],
            req => 1,
        },
        lookup_fields => {
            schema => ['str*'],
            req => 1,
        },
        count => {
            summary => 'Do not output rows, just report the number of rows filled',
            schema => 'bool*',
            cmdline_aliases => {c=>{}},
        },
    },

    reads_multiple_csv => 1,

    tags => ['category:templating'],

    on_begin => sub {
        my $r = shift;

        # check arguments
        @{ $r->{util_args}{input_filenames} } == 2
            or die [400, "Please specify exactly 2 files: target and source"];

        my @lookup_fields; # elem = [fieldname-in-target, fieldname-in-source]
        {
            my @ff = ref($r->{util_args}{lookup_fields}) eq 'ARRAY' ?
                @{$r->{util_args}{lookup_fields}} : split(/,/, $r->{util_args}{lookup_fields});
            for my $field_idx (0..$#ff) {
                my @ff2 = split /:/, $ff[$field_idx], 2;
                if (@ff2 < 2) {
                    $ff2[1] = $ff2[0];
                }
                $lookup_fields[$field_idx] = \@ff2;
            }
        }

        my %fill_fields; # key=fieldname-in-target, val=fieldname-in-source
        {
            my @ff = ref($r->{util_args}{fill_fields}) eq 'ARRAY' ?
                @{$r->{util_args}{fill_fields}} : split(/,/, $r->{util_args}{fill_fields});
            for my $field_idx (0..$#ff) {
                my @ff2 = split /:/, $ff[$field_idx], 2;
                if (@ff2 < 2) {
                    $ff2[1] = $ff2[0];
                }
                $fill_fields{ $ff2[0] } = $ff2[1];
            }
        }

        # these are the keys that we add to the stash
        $r->{lookup_fields} = \@lookup_fields;
        $r->{fill_fields} = \%fill_fields;
        $r->{source_fields_idx} = [];
        $r->{source_fields} = [];
        $r->{source_data_rows} = [];
        $r->{target_fields_idx} = [];
        $r->{target_fields} = [];
        $r->{target_data_rows} = [];
    },

    on_input_header_row => sub {
        my $r = shift;

        if ($r->{input_filenum} == 1) {
            $r->{target_fields}     = $r->{input_fields};
            $r->{target_fields_idx} = $r->{input_fields_idx};
            $r->{output_fields}     = $r->{input_fields};
        } else {
            $r->{source_fields}     = $r->{input_fields};
            $r->{source_fields_idx} = $r->{input_fields_idx};
        }
    },

    on_input_data_row => sub {
        my $r = shift;

        if ($r->{input_filenum} == 1) {
            push @{ $r->{target_data_rows} }, $r->{input_row};
        } else {
            push @{ $r->{source_data_rows} }, $r->{input_row};
        }
    },

    after_close_input_files => sub {
        my $r = shift;

        my $ci = $r->{util_args}{ignore_case};

        # build lookup table
        my %lookup_table; # key = joined lookup fields, val = source row idx
        for my $row_idx (0..$#{$r->{source_data_rows}}) {
            my $row = $r->{source_data_rows}[$row_idx];
            my $key = join "|", map {
                my $field = $r->{lookup_fields}[$_][1];
                my $field_idx = $r->{source_fields_idx}{$field};
                my $val = defined $field_idx ? $row->[$field_idx] : "";
                $val = lc $val if $ci;
                $val;
            } 0..$#{ $r->{lookup_fields} };
            $lookup_table{$key} //= $row_idx;
        }
        #use DD; dd { lookup_fields=>$r->{lookup_fields}, fill_fields=>$r->{fill_fields}, lookup_table=>\%lookup_table };

        # fill target csv
        my $num_filled = 0;

        for my $row (@{ $r->{target_data_rows} }) {
            my $key = join "|", map {
                my $field = $r->{lookup_fields}[$_][0];
                my $field_idx = $r->{target_fields_idx}{$field};
                my $val = defined $field_idx ? $row->[$field_idx] : "";
                $val = lc $val if $ci;
                $val;
            } 0..$#{ $r->{lookup_fields} };

            #say "D:looking up '$key' ...";
            if (defined(my $row_idx = $lookup_table{$key})) {
                #say "  D:found";
                my $row_filled;
                my $source_row = $r->{source_data_rows}[$row_idx];
                for my $field (keys %{$r->{fill_fields}}) {
                    my $target_field_idx = $r->{target_fields_idx}{$field};
                    next unless defined $target_field_idx;
                    my $source_field_idx = $r->{source_fields_idx}{ $r->{fill_fields}{$field} };
                    next unless defined $source_field_idx;
                    $row->[$target_field_idx] =
                        $source_row->[$source_field_idx];
                    $row_filled++;
                }
                $num_filled++ if $row_filled;
            }
            unless ($r->{util_args}{count}) {
                $r->{code_print_row}->($row);
            }
        } # for target data row

        if ($r->{util_args}{count}) {
            $r->{result} = [200, "OK", $num_filled];
        }
    },
);

1;
# ABSTRACT:
