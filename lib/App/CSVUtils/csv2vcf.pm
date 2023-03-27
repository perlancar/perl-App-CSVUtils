package App::CSVUtils::csv2vcf;

use 5.010001;
use strict;
use warnings;
use Log::ger;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(gen_csv_util);

gen_csv_util(
    name => 'csv2vcf',
    summary => 'Create a VCF from selected fields of the CSV',
    description => <<'_',

You can set which CSV fields to use for name, cell phone, and email. If unset,
will guess from the field name. If that also fails, will warn/bail out.

_
    add_args => {
        name_vcf_field => {
            summary => 'Select field to use as VCF N (name) field',
            schema => 'str*',
        },
        cell_vcf_field => {
            summary => 'Select field to use as VCF CELL field',
            schema => 'str*',
        },
        email_vcf_field => {
            summary => 'Select field to use as VCF EMAIL field',
            schema => 'str*',
        },
    },
    tags => ['category:converting', 'format:vcf'],

    examples => [
        {
            summary => 'Create an addressbook from CSV',
            argv => ['addressbook.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    writes_csv => 0,

    on_begin => sub {
        my $r = shift;
        $r->{wants_input_row_as_hashref}++;

        # this is the key we add to the stash
        $r->{vcf} = '';
        $r->{fields_for} = {};
        $r->{fields_for}{N}     = $r->{util_args}{name_vcf_field};
        $r->{fields_for}{CELL}  = $r->{util_args}{cell_vcf_field};
        $r->{fields_for}{EMAIL} = $r->{util_args}{email_vcf_field};
    },

    on_input_header_row => sub {
        my $r = shift;

        for my $field (@{ $r->{input_fields} }) {
            if ($field =~ /name/i && !defined($r->{fields_for}{N})) {
                log_info "Will be using field '$field' for VCF field 'N' (name)";
                $r->{fields_for}{N} = $field;
            }
            if ($field =~ /(e-?)?mail/i && !defined($r->{fields_for}{EMAIL})) {
                log_info "Will be using field '$field' for VCF field 'EMAIL'";
                $r->{fields_for}{EMAIL} = $field;
            }
            if ($field =~ /cell|hp|phone|wa|whatsapp/i && !defined($r->{fields_for}{CELL})) {
                log_info "Will be using field '$field' for VCF field 'CELL' (cellular phone)";
                $r->{fields_for}{CELL} = $field;
            }
        }
        if (!defined($r->{fields_for}{N})) {
            die [412, "Can't convert to VCF because we cannot determine which field to use as the VCF N (name) field"];
        }
        if (!defined($r->{fields_for}{EMAIL})) {
            log_warn "We cannot determine which field to use as the VCF EMAIL field";
        }
        if (!defined($r->{fields_for}{CELL})) {
            log_warn "We cannot determine which field to use as the VCF CELL (cellular phone) field";
        }
    },

    on_input_data_row => sub {
        my $r = shift;

        $r->{vcard} .= join(
            "",
            "BEGIN:VCARD\n",
            "VERSION:3.0\n",
            "N:", $r->{input_row}[$r->{input_fields_idx}{ $r->{fields_for}{N} }], "\n",
            (defined $r->{fields_for}{EMAIL} ? ("EMAIL;type=INTERNET;type=WORK;pref:", $r->{input_row}[$r->{input_fields_idx}{ $r->{fields_for}{EMAIL} }], "\n") : ()),
            (defined $r->{fields_for}{CELL} ? ("TEL;type=CELL:", $r->{input_row}[$r->{input_fields_idx}{ $r->{fields_for}{CELL} }], "\n") : ()),
            "END:VCARD\n\n",
        );
    },

    on_end => sub {
        my $r = shift;
        $r->{result} = [200, "OK", $r->{vcard}];
    },
);

1;
# ABSTRACT:
