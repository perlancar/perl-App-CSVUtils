package App::CSVUtils::csv_join;

use 5.010001;
use strict;
use warnings;

our $AUTHORITY = 'cpan:PERLANCAR'; # AUTHORITY
our $DATE = '2025-02-04'; # DATE
our $DIST = 'App-CSVUtils'; # DIST
our $VERSION = '1.036'; # VERSION

use App::CSVUtils qw(
                        gen_csv_util
                );

gen_csv_util(
    name => 'csv_join',
    summary => 'Join fields from one CSV to another',
    #XXX Update to cover --regex, --fuzzy-fill, --inner
    description => <<'___',

Example input:

    # report.csv
    client_id,followup_staff,followup_note
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

To add `client_email` and `client_phone` fields to `report.csv` from `clients.csv`, we can use:

    % csv-join report.csv clients.csv --lookup-fields client_id:id --fill-fields client_email:email,client_phone:phone

The result will be:

    client_id,followup_staff,followup_note,client_email,client_phone
    101,Jerry,not renewing,andy@example.com,555-2983
    299,Jerry,still thinking over,cindy@example.com,555-7892
    734,Elaine,renewing,felipe@example.com,555-9067

Note: The headers for the the target look-up fields are not required to exist, but will be used if present.
this permits you to control the placement of the new data. If the headers are absent, the new fields will
be appended to right of the the existing the fields.
___

    add_args => {
		 fill_fields => {
				 summary => 'List of source fields to add to target',
				 schema => ['str*'],
				 req => 1,
				 cmdline_aliases => { select=>{} }

				},
		 lookup_fields => {
				   summary => 'Field(s) used to match source records to target',
				   schema => ['str*'],
				   req => 1,
				   cmdline_aliases => { lookup_field=>{}, key=>{}, keys=>{}, on=>{}, where=>{} }
				  },
		 ignore_case => {
				 summary => 'Case insensitive matching of lookup-fields',
				 schema => 'bool*',
				 cmdline_aliases => { ci=>{}, i=>{} }
				},
		 regex => {
			   summary=>'Fuzzy match for specified lookup-fields using Tie::Hash::Regex',
			   schema => ['str*'],
			   cmdline_aliases => { fuzzy=>{} }
			  },
		 regex_fill => {
				 summary => 'Add fuzzy/regex matched source fields to target',
				 schema => 'bool*',
				 cmdline_aliases => { fuzzy_fill=>{} }
				},
		 inner => {
				 summary => 'Returns all possible fuzzy matching fill-fields',
				 schema => 'bool*'
				},
		 key_record_separator => {
					  summary=> 'User definable lookup-field key record separator, analogous to perl -0',
					  schema => 'str*',
					  cmdline_aliases => {'key-sep'=>{}, sep=>{}, 0=>{} }
					 },
		 count => {
			   summary => 'Do not output rows, just report the number of rows filled',
			   schema => 'bool*',
			   cmdline_aliases => { c=>{} }
			  }
    },

    reads_multiple_csv => 1,

    tags => ['category:templating'],

    on_begin => sub {
        my $r = shift;

        # check arguments
        @{ $r->{util_args}{input_filenames} } == 2
            or die [400, "Please specify exactly 2 files: target and source"];
	#XXX no overlap between --lookup-fields and --regex?

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
        my @fuzzy; # elem = [fieldname-in-target, fieldname-in-source]
        {
            my @ff = ref($r->{util_args}{regex}) eq 'ARRAY' ?
                @{$r->{util_args}{regex}} : split(/,/, $r->{util_args}{regex});
            for my $field_idx (0..$#ff) {
                my @ff2 = split /:/, $ff[$field_idx], 2;
                if (@ff2 < 2) {
                    $ff2[1] = $ff2[0];
                }
                $fuzzy[$field_idx] = \@ff2;
            }
        }
	my %fuzzy = map {$_->[0]=>1, $_->[1]=>1} @fuzzy;
	map { die [400, "Cannot use the same field for both exact and fuzzy expression matching"] if
		  $fuzzy{$_->[0]} or  $fuzzy{$_->[1]} } @lookup_fields;


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
	$r->{fuzzy} = \@fuzzy;
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

	#TARGET
        if ($r->{input_filenum} == 1) {
	    #JDP: Optionally append fuzzy matched target fields
	    if( $r->{util_args}{regex_fill} ){
		$r->{fill_fields}->{ join '.', @{$_} }=$_->[1] foreach
		    @{$r->{fuzzy}};
	    }

	    #JDP: lookup-fields has undocumented expectation of headers for
	    #     empty target columns. This provides more DWIM behavior by
	    #     patching in implicit headers a la csv-add-fields
	    my $target_count = @{ $r->{input_fields} };
	    my %target_fields = map {$_=>1} @{ $r->{input_fields} };
	    foreach my $field ( keys %{ $r->{fill_fields} } ){
		unless( exists($target_fields{$field}) ){
		    push @{ $r->{input_fields} }, $field;
		    $r->{input_fields_idx}->{$field}=$target_count++;
		}
	    }

	    $r->{target_fields}     = $r->{input_fields};
	    $r->{target_fields_idx} = $r->{input_fields_idx};
	    $r->{output_fields}     = $r->{input_fields};

	    #JDP: Check join field names exist
	    #XXX Case-insensitivity?
	    foreach( @{$r->{lookup_fields}}, @{$r->{fuzzy}} ){
		my $out = $_->[0];
		die [404, "Unknown target field: $out"] unless
		    $r->{input_filenum}==1 && exists $r->{target_fields_idx}->{$out};
	    }
	    foreach my $k ( keys %{$r->{fill_fields}} ){
		die [404, "Unknown target fill field: $k"] unless
		    $r->{input_filenum}==1 && exists $r->{target_fields_idx}->{$k};
	    }

	#SOURCE
	} else {
            $r->{source_fields}     = $r->{input_fields};
            $r->{source_fields_idx} = $r->{input_fields_idx};

	    #JDP: Check join field names exist
	    #XXX Case-insensitivity?
	    foreach( @{$r->{lookup_fields}}, @{$r->{fuzzy}} ){
		my $src = $_->[1];
		die [404, "Unknown source field: $src"] unless
		$r->{input_filenum}==2 && exists $r->{source_fields_idx}->{$src};
	    }
	    foreach my $v ( values %{$r->{fill_fields}} ){
		die [404, "Unknown source fill field: $v"] unless
		    $r->{input_filenum}!=1 && exists $r->{source_fields_idx}->{$v};
	    }

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
      #my $fuzzy = exists($r->{util_args}{regex}) ? 1 : 0;
      my $fuzzy = scalar @{ $r->{fuzzy} };

      #Prep key separator. Original use of | is a bad option for fuzzy regex mode
      my $keySepIN = $r->{util_args}{key_record_separator};
      my $keySep = eval{chr("0$1")} if defined($keySepIN) && $keySepIN =~ /^0(x\{?[0-9a-fA-F]+\}?|[0-9+]{2})$/;
      $keySep = "\000" if $@;
      $keySep //= "\000";

      my @inner;
      my $inner = $r->{util_args}{inner};
      eval 'use Storable' if $inner;
      if( $@ ){
	  warn "Cannot load Storable, unable to fulfill --inner: $@\n";
	  $inner = 0 }

      # build lookup table w/ C-style loop for efficiency on large files
      my %lookup_table; # key = joined lookup fields, val = source row idx
      for(my $row_idx=0; $row_idx<=$#{$r->{source_data_rows}}; $row_idx++) {
	  my($row, $key1, $key2);
	  $row = $r->{source_data_rows}[$row_idx];
	  $key1 = join $keySep, map {
	      my $field = $r->{lookup_fields}[$_][1];
	      my $field_idx = $r->{source_fields_idx}->{$field};
	      my $val = defined $field_idx ? $row->[$field_idx] : "";
	      $val = lc $val if $ci;
	      $val;
	  } 0..$#{ $r->{lookup_fields} };
	  if( $fuzzy ){
	      $key2 = join $keySep, map {
		  my $field = $r->{fuzzy}[$_][1];
		  my $field_idx = $r->{source_fields_idx}{$field};
		  my $val = defined $field_idx ? $row->[$field_idx] : '';
		  $val = lc $val if $ci;
	      } 0..$#{ $r->{fuzzy} };
	  }
	  else{
	      $key2 = 'STATIC' }
	  #JDP: Split key greatly improves fuzzy match performance by binning data,
	  #     thereby reducing pool of values to check with any given regexp
	  $lookup_table{$key1}->{$key2} //= $row_idx;
	  #warn "Prepped key1($key1)\tkey2($key2) for $row_idx\n"# unless $row_idx %20;
      }
      #use DD; dd { lookup_fields=>$r->{lookup_fields}, fill_fields=>$r->{fill_fields}, lookup_table=>\%lookup_table };

      # fill target csv
      my $rows_filled = 0;

      for(my $i=0; $i<=$#{ $r->{target_data_rows} }; $i++){
	my $row = $r->{target_data_rows}->[$i];
	my($key1, $key2);

	$key1 = join $keySep, map {
	    my $field = $r->{lookup_fields}[$_][0];
	    my $field_idx = $r->{target_fields_idx}{$field};
	    my $val = defined $field_idx ? $row->[$field_idx] : "";
	    $val = lc $val if $ci;
	    $val;
	} 0..$#{ $r->{lookup_fields} };
	if( $fuzzy ){
	    $key2 = join '.*?'.$keySep, map {
		my $field = $r->{fuzzy}[$_][0];
		my $field_idx = $r->{target_fields_idx}{$field};
		my $val = defined $field_idx ? $row->[$field_idx] : '';
		$val = lc $val if $ci;
		#JDP: Wrapping is superfluous if single fuzzy key,
		#     as is explicit match anything at beginning and ending of key
		#     post-wrap is handled in join to reduce testing of $_
		my $prewrap  = $_==0 ? '' : '.*?';
		$fuzzy >1 ? $prewrap . quotemeta($val) : quotemeta($val);
	    } 0..$#{ $r->{fuzzy} };
	}
	else{
	    $key2 = 'STATIC' }


	#say "D:looking up '$key1'\t'$key2' ...";
	my(@row_idx, $K1LUT);
	#JDP: explore MCE for performance boost?
	if( defined($K1LUT = $lookup_table{$key1}) ){
	    #warn "Matched $key1\n";
	    unless( $fuzzy ){
		@row_idx = ($K1LUT->{STATIC}) }
	    else{
		$key2 = qr/$key2/;
		foreach my $TK2 ( keys %{$K1LUT} ){
		    push(@row_idx, $K1LUT->{$TK2}) if $TK2 =~ /$key2/;
		    #warn "$key1: Testing $TK2 =~ /$key2/ (@{[ $TK2 =~ /$key2/ ]})\t$K1LUT->{$TK2}\n" if $key1 == 734;

		    #JDP: Short-circuit unless inner join requested
		    last if scalar @row_idx && !$inner;
		}
	    }

	    #say "  D:found";
	    for(my $j=0; $j<=$#row_idx; $j++ ){
		my $row = $row;
		my $fields_filled;
		my $row_idx = $row_idx[$j];
		my $source_row = $r->{source_data_rows}[$row_idx];

		$row = Storable::dclone($r->{target_data_rows}->[$i]) if $fuzzy && $j && $inner;

		for my $field (keys %{$r->{fill_fields}}) {
		    my $target_field_idx = $r->{target_fields_idx}{$field};
		    #JDP: Why is this being checked every time? $r->{target_fields_idx} does not change.
		    #     There isn't even a clear way for its values to be undef
		    #next unless defined $target_field_idx;

		    my $source_field_idx = $r->{source_fields_idx}{ $r->{fill_fields}{$field} };
		    #JDP: Why is this being checked every time? $r->{source_fields_idx} does not change
		    #     There isn't even a clear way for its values to be undef
		    #next unless defined $source_field_idx;

		    $row->[$target_field_idx] = $source_row->[$source_field_idx];
		    $fields_filled++;
		}

		push @inner, $row if $fuzzy && $j && $inner;
		$rows_filled++ if $fields_filled;
	    }
	}

	#XXX: would be VERY nice to print as we go rather than spool everything, esp. for large files
	unless ($r->{util_args}{count}) {
	  $r->{code_print_row}->($row);
	}
      } # for target data row


      #JDP: Inner fill, append multi-matched fuzzy source rows
      if( $inner ){
	  foreach my $row ( @inner ){
	      $r->{code_print_row}->($row);
	  }
      }


      if ($r->{util_args}{count}) {
	$r->{result} = [200, "OK", $rows_filled];
      }
    }
);

1;
# ABSTRACT: Fill fields of a CSV file from another

__END__

=pod

=encoding UTF-8

=head1 NAME

App::CSVUtils::csv_join - Fill fields of a CSV file from another

=head1 VERSION

This document describes version 1.036 of App::CSVUtils::csv_join (from Perl distribution App-CSVUtils), released on 2025-02-04.

=head1 FUNCTIONS


=head2 csv_join

Usage:

 csv_join(%args) -> [$status_code, $reason, $payload, \%result_meta]

Join fields from one CSV to another

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

To fill up the C<client_email> and C<client_phone> fields of C<report.csv> from
C<clients.csv>, we can use:

 % csv-join report.csv clients.csv --lookup-fields client_id:id --fill-fields client_email:email,client_phone:phone

The result will be:

 client_id,followup_staff,followup_note,client_email,client_phone
 101,Jerry,not renewing,andy@example.com,555-2983
 299,Jerry,still thinking over,cindy@example.com,555-7892
 734,Elaine,renewing,felipe@example.com,555-9067

Arguments ('*' denotes required arguments):

=over 4

=item * B<lookup_fields>* => I<str>

Field(s) used to match source records to target.

This is a comma separated list of field name pairs, with the target field name given first
followed by a colon and the source field name. The colon and source field name may be omitted
if they are identical to the target. i.e, the following are equiavalent:

    --lookup-fields ID:ID

    --lookup-fields ID

=item * B<fill_fields>* => I<str>

List of source fields to add to target.

NOTE: When multiple source records could be used to fill via B<lookup-fields>,
the last matching source record is used. When multiple source records match
B<regex>, a random selection among them is used unless B<inner> is enabled.

=item * B<inner> => I<bool>

Returns multiple records, one each for all possible matching B<fill-fields>
when using B<regex>.

=item * B<ignore_case> => I<bool>

Case insensitive matching of look-up field values.

Note: Field name designations for B<lookup-fields>, B<fill-fields> or B<regex>
are I<always case sensitive>, regardless of the setting of this option.

=item * B<regex>* => I<str>

Implements basic fuzzy matching of the specified look-up fields
in a manner similar to L<Tie::Hash::Regex> by wrapping the
target look-up values with .*? Thus permitting a target of

    123 Main St

to match a source cell with

    123 Main Street

by looking for the regular expression

    .*?123 Main st.*?

rather than literal equality with the original cell value.

=item * B<regex-fill> => I<bool>

Adds extra look-up fields with the values of the matched regex fields.
The fields are named

=item * B<count> => I<bool>

Do not output rows, just report the number of rows filled.

=item * B<inplace> => I<true>

Output to the same file as input.

Normally, you output to a different file than input. If you try to output to the
same file (C<-o INPUT.csv -O>) you will clobber the input file; thus the utility
prevents you from doing it. However, with this C<--inplace> option, you can
output to the same file. Like perl's C<-i> option, this will first output to a
temporary file in the same directory as the input file then rename to the final
file at the end. You cannot specify output file (C<-o>) when using this option,
but you can specify backup extension with C<-b> option.

Some caveats:

=over

=item * if input file is a symbolic link, it will be replaced with a regular file;

=item * renaming (implemented using C<rename()>) can fail if input filename is too long;

=item * value specified in C<-b> is currently not checked for acceptable characters;

=item * things can also fail if permissions are restrictive;

=back

=item * B<inplace_backup_ext> => I<str> (default: "")

Extension to add for backup of input file.

In inplace mode (C<--inplace>), if this option is set to a non-empty string, will
rename the input file using this extension as a backup. The old existing backup
will be overwritten, if any.

=item * B<input_escape_char> => I<str>

Specify character to escape value in field in input CSV, will be passed to Text::CSV_XS.

Defaults to C<\\> (backslash). Overrides C<--input-tsv> option.

=item * B<input_filenames> => I<array[filename]> (default: ["-"])

Input CSV files.

Use C<-> to read from stdin.

Encoding of input file is assumed to be UTF-8.

=item * B<input_header> => I<bool> (default: 1)

Specify whether input CSV has a header row.

By default, the first row of the input CSV will be assumed to contain field
names (and the second row contains the first data row). When you declare that
input CSV does not have header row (C<--no-input-header>), the first row of the
CSV is assumed to contain the first data row. Fields will be named C<field1>,
C<field2>, and so on.

=item * B<input_quote_char> => I<str>

Specify field quote character in input CSV, will be passed to Text::CSV_XS.

Defaults to C<"> (double quote). Overrides C<--input-tsv> option.

=item * B<input_sep_char> => I<str>

Specify field separator character in input CSV, will be passed to Text::CSV_XS.

Defaults to C<,> (comma). Overrides C<--input-tsv> option.

=item * B<input_skip_num_lines> => I<posint>

Number of lines to skip before header row.

This can be useful if you have a CSV files (usually some generated reports,
sometimes converted from spreadsheet) that have additional header lines or info
before the CSV header row.

See also the alternative option: C<--input-skip-until-pattern>.

=item * B<input_skip_until_pattern> => I<re_from_str>

Skip rows until the first header row matches a regex pattern.

This is an alternative to the C<--input-skip-num-lines> and can be useful if you
have a CSV files (usually some generated reports, sometimes converted from
spreadsheet) that have additional header lines or info before the CSV header
row.

With C<--input-skip-num-lines>, you skip a fixed number of lines. With this
option, rows will be skipped until the first field matches the specified regex
pattern.

=item * B<input_tsv> => I<true>

Inform that input file is in TSV (tab-separated) format instead of CSV.

Overriden by C<--input-sep-char>, C<--input-quote-char>, C<--input-escape-char>
options. If one of those options is specified, then C<--input-tsv> will be
ignored.

=item * B<output_always_quote> => I<bool> (default: 0)

Whether to always quote values.

When set to false (the default), values are quoted only when necessary:

 field1,field2,"field three contains comma (,)",field4

When set to true, then all values will be quoted:

 "field1","field2","field three contains comma (,)","field4"

=item * B<output_escape_char> => I<str>

Specify character to escape value in field in output CSV, will be passed to Text::CSV_XS.

This is like C<--input-escape-char> option but for output instead of input.

Defaults to C<\\> (backslash). Overrides C<--output-tsv> option.

=item * B<output_filename> => I<filename>

Output filename.

Use C<-> to output to stdout (the default if you don't specify this option).

Encoding of output file is assumed to be UTF-8.

=item * B<output_header> => I<bool>

Whether output CSV should have a header row.

By default, a header row will be output I<if> input CSV has header row. Under
C<--output-header>, a header row will be output even if input CSV does not have
header row (value will be something like "col0,col1,..."). Under
C<--no-output-header>, header row will I<not> be printed even if input CSV has
header row. So this option can be used to unconditionally add or remove header
row.

=item * B<output_quote_char> => I<str>

Specify field quote character in output CSV, will be passed to Text::CSV_XS.

This is like C<--input-quote-char> option but for output instead of input.

Defaults to C<"> (double quote). Overrides C<--output-tsv> option.

=item * B<output_quote_empty> => I<bool> (default: 0)

Whether to quote empty values.

When set to false (the default), empty values are not quoted:

 field1,field2,,field4

When set to true, then empty values will be quoted:

 field1,field2,"",field4

=item * B<output_sep_char> => I<str>

Specify field separator character in output CSV, will be passed to Text::CSV_XS.

This is like C<--input-sep-char> option but for output instead of input.

Defaults to C<,> (comma). Overrides C<--output-tsv> option.

=item * B<output_tsv> => I<bool>

Inform that output file is TSV (tab-separated) format instead of CSV.

This is like C<--input-tsv> option but for output instead of input.

Overriden by C<--output-sep-char>, C<--output-quote-char>, C<--output-escape-char>
options. If one of those options is specified, then C<--output-tsv> will be
ignored.

=item * B<overwrite> => I<bool>

Whether to override existing output file.


=back

Returns an enveloped result (an array).

First element ($status_code) is an integer containing HTTP-like status code
(200 means OK, 4xx caller error, 5xx function error). Second element
($reason) is a string containing error message, or something like "OK" if status is
200. Third element ($payload) is the actual result, but usually not present when enveloped result is an error response ($status_code is not 2xx). Fourth
element (%result_meta) is called result metadata and is optional, a hash
that contains extra information, much like how HTTP response headers provide additional metadata.

Return value:  (any)

=head1 HOMEPAGE

Please visit the project's homepage at L<https://metacpan.org/release/App-CSVUtils>.

=head1 SOURCE

Source repository is at L<https://github.com/perlancar/perl-App-CSVUtils>.

=head1 AUTHOR

perlancar <perlancar@cpan.org>

=head1 CONTRIBUTING


To contribute, you can send patches by email/via RT, or send pull requests on
GitHub.

Most of the time, you don't need to build the distribution yourself. You can
simply modify the code, then test via:

 % prove -l

If you want to build the distribution (e.g. to try to install it locally on your
system), you can install L<Dist::Zilla>,
L<Dist::Zilla::PluginBundle::Author::PERLANCAR>,
L<Pod::Weaver::PluginBundle::Author::PERLANCAR>, and sometimes one or two other
Dist::Zilla- and/or Pod::Weaver plugins. Any additional steps required beyond
that are considered a bug and can be reported to me.

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2025 by perlancar <perlancar@cpan.org>
and Jerrad Pierce <jpierce@cpan.org>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website L<https://rt.cpan.org/Public/Dist/Display.html?Name=App-CSVUtils>

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=cut
