#!perl

use 5.010001;
use strict;
use warnings;
use Test::Exception;
use Test::More 0.98;

use App::CSVUtils;
use File::Temp qw(tempdir);
use File::Slurper qw(write_text);

my $dir = tempdir(CLEANUP => 1);
write_text("$dir/1.csv", "f1,f2,f3\n1,2,3\n4,5,6\n7,8,9\n");
write_text("$dir/2.csv", "f1\n1\n2\n3\n");
write_text("$dir/3.csv", qq(f1,f2\n1,"row\n1"\n2,"row\n2"\n));

subtest csv_add_field => sub {
    my $res;

    dies_ok { App::CSVUtils::csv_add_field(filename=>"$dir/1.csv", field=>"f4", eval=>"blah") }
        "error in eval code -> dies";

    $res = App::CSVUtils::csv_add_field(filename=>"$dir/1.csv", field=>"f3", eval=>"1");
    is($res->[0], 412, "adding existing field -> error");

    $res = App::CSVUtils::csv_add_field(filename=>"$dir/1.csv", field=>"", eval=>"1");
    is($res->[0], 400, "empty field -> error");

    $res = App::CSVUtils::csv_add_field(filename=>"$dir/1.csv", field=>"f4", eval=>'$main::rownum*2');
    is_deeply($res, [200,"OK","f1,f2,f3,f4\n1,2,3,4\n4,5,6,6\n7,8,9,8\n",{'cmdline.skip_format'=>1}], "result");
};

subtest csv_delete_field => sub {
    my $res;

    dies_ok { App::CSVUtils::csv_delete_field(filename=>"$dir/1.csv", field=>"f4") }
        "deleting unknown field -> dies";

    $res = App::CSVUtils::csv_delete_field(filename=>"$dir/2.csv", field=>"f1");
    is($res->[0], 412, "deleting last field -> error");

    $res = App::CSVUtils::csv_delete_field(filename=>"$dir/1.csv", field=>"f1");
    is_deeply($res, [200,"OK","f2,f3\n2,3\n5,6\n8,9\n",{'cmdline.skip_format'=>1}], "result");
};

subtest csv_list_field_names => sub {
    my $res;

    $res = App::CSVUtils::csv_list_field_names(filename=>"$dir/1.csv");
    is_deeply($res, [200,"OK",[{name=>'f1',index=>1},{name=>'f2',index=>2},{name=>'f3',index=>3}],{'table.fields'=>[qw/name index/]}], "result");
};

subtest csv_munge_field => sub {
    my $res;

    dies_ok { App::CSVUtils::csv_munge_field(filename=>"$dir/1.csv", field=>"f1", eval=>"blah") }
        "error in code -> dies";

    dies_ok { App::CSVUtils::csv_munge_field(filename=>"$dir/1.csv", field=>"f4", eval=>'1') }
        "munging unknown field -> dies";

    $res = App::CSVUtils::csv_munge_field(filename=>"$dir/1.csv", field=>"f3", eval=>'$_ = $_*3 if $main::rownum > 1');
    is_deeply($res, [200,"OK","f1,f2,f3\n1,2,9\n4,5,18\n7,8,27\n",{'cmdline.skip_format'=>1}], "result");
};

subtest csv_replace_newline => sub {
    my $res;

    $res = App::CSVUtils::csv_replace_newline(filename=>"$dir/3.csv", with=>" ");
    is_deeply($res, [200,"OK",qq(f1,f2\n1,"row 1"\n2,"row 2"\n),{'cmdline.skip_format'=>1}], "result");
    # XXX opt=with
};

done_testing;
