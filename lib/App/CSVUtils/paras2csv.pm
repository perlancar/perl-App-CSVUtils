package App::CSVUtils::paras2csv;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(gen_csv_util);

sub _unescape_field {
    my $val = shift;
    $val =~ s/(\\:|\\n|\\\\|[^\\:]+)/$1 eq "\\\\" ? "\\" : $1 eq "\\n" ? "\n" : $1 eq "\\:" ? ":" : $1/eg;
    $val;
}

sub _unescape_value {
    my $val = shift;
    $val =~ s/(\\n|\\\\|[^\\]+)/$1 eq "\\\\" ? "\\" : $1 eq "\\n" ? "\n" : $1/eg;
    $val;
}

sub _parse_line {
    my $line = shift;
    $line =~ s/\R //g;
    $line =~ /((?:[^\\:]+|\\n|\\\\|\\:)+): (.*)/ or return;
    my $field = _unescape_field($1);
    my $value = _unescape_value($2);
    ($field, $value);
}

sub _parse_para {
    my ($r, $para, $idx) = @_;

    my @h;
    while ($para =~ s/\A(.+(?:\R .*)*)(?:\R|\z)//g) {
        #say "D:line=<$1>, para=<$para>";
        my ($field, $val) = _parse_line($1);
        defined $field or die [400, "Paragraph[$idx]: Can't parse line $1"];
        if ($r->{util_args}{trim_header}) {
            $field =~ s/\A\s+//;
            $field =~ s/\s+\z//;
        } elsif ($r->{util_args}{ltrim_header}) {
            $field =~ s/\A\s+//;
        } elsif ($r->{util_args}{rtrim_header}) {
            $field =~ s/\s+\z//;
        }
        push @h, $field, $val;
    }
    @h;
}

gen_csv_util(
    name => 'paras2csv',
    summary => 'Convert paragraphs to CSV',
    description => <<'MARKDOWN',

This utility is the counterpart of the <prog:csv2paras> utility. See its
documentation for more details.

Keywords: paragraphs, cards, pages, headers

MARKDOWN
    add_args => {
        input_file => {
            schema => 'filename*',
            default => '-',
            pos => 0,
        },
        trim_header => {
            schema => 'bool*',
        },
        rtrim_header => {
            schema => 'bool*',
        },
        ltrim_header => {
            schema => 'bool*',
        },
    },
    add_args_rels => {
        'choose_one&' => [ [qw/trim_header rtrim_header ltrim_header/] ],
    },
    links => [
        {url=>'prog:csv2paras'},
    ],
    tags => ['category:converting'],

    examples => [
        {
            summary => 'Convert paragraphs format to CSV',
            src => '[[prog]] - OUTPUT.csv',
            src_plang => 'bash',
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    reads_csv => 0,

    after_read_input => sub {
        my $r = shift;

        my $fh;
        if ($r->{util_args}{input_file} eq '-') {
            $fh = \*STDIN;
        } else {
            open $fh, "<", $r->{util_args}{input_file}
                or die [500, "Can't read file '$r->{util_args}{input_file}: $!"];
        }

        local $/ = "";
        my $i = 0;
        while (my $para = <$fh>) {
            $para =~ s/\R{2}\z//;
            #say "D:para=<$para>";
            my @h = _parse_para($r, $para, $i);
            $i++;
            if ($i == 1) {
                my @h2 = @h;
                my $j = 0;
                while (my ($field, $value) = splice @h2, 0, 2) {
                    $r->{output_fields}[$j] = $field;
                    $r->{output_fields_idx}{$field} = $j;
                    $j++;
                }
            }
            my @vals;
            while (my ($field, $value) = splice @h, 0, 2) {
                push @vals, $value;
            }
            $r->{code_print_row}->(\@vals);
        }
    },
);

1;
# ABSTRACT:
