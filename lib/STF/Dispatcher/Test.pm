package STF::Dispatcher::Test;
use strict;
use base qw(Exporter);
use Plack::Test ();
use HTTP::Date ();
use HTTP::Request::Common qw(PUT HEAD GET DELETE POST);
use Test::More;

our @EXPORT = qw( test_stf_impl );

sub test_stf_impl {
    my $impl = shift;
    Plack::Test::test_psgi(
        app => STF::Dispatcher::PSGI->new( impl => $impl )->to_app,
        client => \&run_tests,
    );
}

sub run_tests {
    my $cb = shift;

    my $res;
    my $randstr = sub {
        my $len = shift;
        my @chars = ('a'..'z', 0..9);
        return join '', map { $chars[rand @chars] } 1..$len;
    };
    my $bucket_name = $randstr->(8);
    my $object_name = join "/", map { $randstr->(8) } 1..4;

    $res = $cb->(
        PUT "http://127.0.0.1/$bucket_name/should_fail"
    );
    if (! ok ! $res->is_success, "bucket creation request with object_name should fail") {
        diag $res->as_string;
    }

    $res = $cb->(
        PUT "http://127.0.0.1/$bucket_name"
    );
    if (! ok $res->is_success, "bucket creation request was successful") {
        diag $res->as_string;
    }

    # Creating a bucket again should respond with a 204
    $res = $cb->(
        PUT "http://127.0.0.1/$bucket_name"
    );
    if (! ok $res->is_success, "bucket creation request (again) was successful") {
        diag $res->as_string;
    }
    if (! is $res->code, 204, "status should be 204") {
        diag $res->as_string;
    }

    my $content = join ".", $$, time(), {}, rand();

    # Creating an object with non-existent bucket should fail
    $res = $cb->(
        PUT "http://127.0.0.1/$bucket_name-non-existent/$object_name",
            "X-Replication-Count" => 3,
            "Content-Type" => "text/plain",
            Content => $content,
    );
    if (! ok ! $res->is_success, "object creation request should fail") {
        diag $res->as_string;
    }

    # Creating an object without giving an object name should fail
    $res = $cb->(
        PUT "http://127.0.0.1/$bucket_name",
            "X-Replication-Count" => 3,
            "Content-Type" => "text/plain",
            Content => $content,
    );
    if (! ok ! $res->is_success, "object creation request should fail") {
        diag $res->as_string;
    }

    # normal object creation
    $res = $cb->(
        PUT "http://127.0.0.1/$bucket_name/$object_name",
            "X-Replication-Count" => 3,
            "Content-Type" => "text/plain",
            Content => $content,
    );
    if (! ok $res->is_success, "object creation request was successful") {
        diag $res->as_string;
    }

    # Get an object with a bad object name
    $res = $cb->(
        GET "http://127.0.0.1/$bucket_name/$object_name-non-existent",
    );
    if (! ok ! $res->is_success, "object fetch request should fail") {
        diag $res->as_string;
    }

    $res = $cb->(
        GET "http://127.0.0.1/$bucket_name/$object_name",
    );
    is $res->content, $content, "content matches";
    is $res->header('X-Content-Type-Options'), 'nosniff', "nosniff is on";

    if ( my $last_mod = $res->header('Last-Modified') ) {
        my $last_mod_t = HTTP::Date::str2time($last_mod);
        $res = $cb->(
            GET "http://127.0.0.1/$bucket_name/$object_name",
                "If-Modified-Since" => $last_mod
        );
        if ( ! is $res->code, 200, "code is 200") {
            diag $res->as_string;
        }
        is $res->header('X-Content-Type-Options'), 'nosniff', "nosniff is on";

        $res = $cb->(
            GET "http://127.0.0.1/$bucket_name/$object_name",
                "If-Modified-Since" => HTTP::Date::time2str($last_mod_t - 30)
        );
        if (! is $res->code, 304, "code is 304!") {
            diag $res->as_string;
        }
    }


    TODO: {
        # Content-Type handling should probably be removed from
        # STF::Dispatcher
        todo_skip "This is probably not necessary", 1;
        is $res->content_type, "text/plain", "content type matches";
    }

    $res = $cb->(
        HEAD "http://127.0.0.1/$bucket_name/$object_name",
    );
    ok $res->is_success, "HEAD works";
    ok ! $res->content, "Should have no body";

    # Modify the object
    $res = $cb->(
        POST "http://127.0.0.1/$bucket_name/$object_name",
    );
    ok $res->is_success, "POST works";


    # Deleting an object with a bad bucket name
    $res = $cb->(
        DELETE "http://127.0.0.1/$bucket_name-non-existent/$object_name"
    );
    if (! ok ! $res->is_success, "object deletion request should fail") {
        diag $res->as_string;
    }

    # Deleting an object with a bad object name
    $res = $cb->(
        DELETE "http://127.0.0.1/$bucket_name/$object_name-non-existent"
    );
    if (! ok ! $res->is_success, "object deletion request should fail") {
        diag $res->as_string;
    }

    # Normal object deletion
    $res = $cb->(
        DELETE "http://127.0.0.1/$bucket_name/$object_name"
    );
    if (! ok $res->is_success, "object deletion request was successful") {
        diag $res->as_string;
    }

    # now that the object is deleted, this should fail
    $res = $cb->(
        GET "http://127.0.0.1/$bucket_name/$object_name",
    );
    if (! is $res->code, 404, "get after delete is 404" ) {
        diag $res->as_string;
    }
    is $res->header('X-Content-Type-Options'), 'nosniff', "nosniff is on";

    # non-existent bucket deletion should fail
    $res = $cb->(
        DELETE "http://127.0.0.1/$bucket_name-non-existent"
    );
    if (! is $res->code, 404, "bucket deletion request was 404") {
        diag $res->as_string;
    }

    # normal bucket deletion
    $res = $cb->(
        DELETE "http://127.0.0.1/$bucket_name"
    );
    if (! is $res->code, 204, "bucket deletion request was 204") {
        diag $res->as_string;
    }
}

1;

__END__

=head1 NAME

STF::Dispatcher::Test - Basic Tests For STF Implementations

=head1 SYNOPSIS

    use Test::More;
    use STF::Dispatcher::Test;

    test_stf_impl My::STF::Impl->new;

    done_testing;

=cut
