package App::CSVUtils::csv2paras;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(gen_csv_util);
use String::Pad qw(pad);

sub _escape_value {
    my $val = shift;
    $val =~ s/(\\|\n)/$1 eq "\\" ? "\\\\" : "\\n\n "/eg;
    $val;
}

sub _escape_header {
    my $val = shift;
    $val =~ s/(\\|\n|:)/$1 eq "\\" ? "\\\\" : $1 eq ":" ? "\\:" : "\\n\n "/eg;
    $val;
}

gen_csv_util(
    name => 'csv2paras',
    summary => 'Convert CSV to paragraphs',
    description => <<'_',

This utility converts CSV format like this:

    name,email,phone,notes
    bill,bill@example.com,555-1236,+
    lisa,lisa@example.com,555-1235,from work
    jimmy,jimmy@example.com,555-1237,

into paragraphs format like this, which resembles (but not strictly follows)
email headers (RFC-822) or internet message headers (RFC-5322):

    name: bill
    email: bill@example.com
    phone: 555-1236
    notes: +

    name: lisa
    email: lisa@example.com
    phone: 555-1235
    notes: from work

    name: jimmy
    email: jimmy@example.com
    phone: 555-1237
    notes:

Why display in this format? It might be more visually readable or diff-able
especially if there are a lot of fields and/or there are long values.

If a CSV value contains newline, it will escaped "\n", e.g.:

    # CSV
    name,email,phone,notes
    beth,beth@example.com,555-1231,"Has no last name
    Might be adopted sometime by Jimmy"
    matthew,matthew@example.com,555-1239,"Quit

      or fired?"

    # paragraph
    name: beth
    email: beth@example.com
    phone: 555-1231
    notes: Has no last name\nMight be adopted sometime by Jimmy

    name: matthew
    email: matthew@example.com
    phone: 555-1239
    notes: Quit\n\n  or fired?

If a CSV value contains literal "\" (backslash) it will be escaped as "\\".

Long lines are also by default folded at 78 columns (but you can customize with
the `--width` option); if a line is folded a literal backslash is added to the
end of each physical line and the next line will be indented by two spaces:

    notes: This is a long note. This is a long note. This is a long note. This is\
      a long note. This is a long note.

A long word is also folded and the next line will be indented by one space:

    notes: Thisisalongwordthisisalongwordthisisalongwordthisisalongwordthisisalongw\
     ord

Newline and backslash are also escaped in header; additionally a literal ":"
(colon) is escaped into "\:".

There is option to skip displaying empty fields (`--hide-empty-values`) and to
align the ":" header separator.

Keywords: paragraphs, cards, pages, headers

_
    add_args => {
        width => {
            summary => 'The width at which to fold long lines, -1 means to never fold',
            schema => ['int*', 'clset|'=>[{is=>-1, "is.err_msg"=>"Must be >0 or -1"}, {min=>1}]],
            default => 78,
        },
        hide_empty_values => {
            summary => 'Whether to skip showing empty values',
            schema => 'bool*',
        },
        align => {
            summary => 'Whether to align header separator across lines',
            schema => 'bool*',
            description => <<'_',

Note that if you want to convert the paragraphs back to CSV later using
<prog:paras2csv>, the padding spaces added by this option will become part of
header value, unless you use its `--trim-header` or `--rtrim-header` option.

_
        },
    },
    links => [
        {url=>'prog:paras2csv'},
    ],
    examples => [
        {
            summary => 'Convert to paragraphs format, show fields alphabetically, do not fold, hide empty values',
            src => 'csv-sort-fields INPUT.csv | [[prog]] --width=-1 --hide-empty-values',
            src_plang => 'bash',
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    on_input_header_row => sub {
        my $r = shift;

        # these are the keys we add to the stash
        $r->{escaped_headers} = [];
        $r->{longest_header_len} = 0;

        for my $field (@{ $r->{input_fields} }) {
            push @{ $r->{escaped_headers} }, _escape_header($field);
            my $l = length($r->{escaped_headers}[-1]);
            $r->{longest_header_len} = $l if $r->{longest_header_len} < $l;
        }
    },

    on_input_data_row => sub {
        my $r = shift;

        print "\n" if $r->{input_data_rownum} > 1;

        for my $i (0 .. $#{ $r->{input_fields} }) {
            my $val = $r->{input_row}[$i];
            next if $r->{util_args}{hide_empty_values} && length $val == 0;
            my $line =
                ($r->{util_args}{align} ? pad($r->{escaped_headers}[$i], $r->{longest_header_len}, "r") : $r->{escaped_headers}[$i]).
                ": ".
                _escape_value($val);
            if ($r->{util_args}{width} == -1 || length($line) <= $r->{util_args}{width}) {
                print $line, "\n";
            } else {
                require Text::Wrap::NoStrip;
                local $Text::Wrap::NoStrip::columns = $r->{util_args}{width};
                my $wrapped_line = Text::Wrap::NoStrip::wrap("", " ", $line);
                $wrapped_line =~ s!$(?=.)!\\!gm;
                print $wrapped_line, "\n";
            }
        }
    },

    writes_csv => 0,
);

1;
# ABSTRACT:

=head1 SEE ALSO

L<Acme::MetaSyntactic::newsradio>
