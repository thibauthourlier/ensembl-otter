package Bio::Otter::Auth::SSO;
use strict;
use warnings;

use URI::Escape qw{ uri_escape };
use HTTP::Request;


=head1 NAME

Bio::Otter::Auth::SSO - support for "legacy" login service

=head1 DESCRIPTION

Implements login (for client) and authentication (for server).

The caller must provide the relevant supporting objects:
L<LWP::UserAgent> on the client, L<SangerWeb> on the server.

=head1 CLASS METHODS

=head2 login($fetcher, $user, $pass)

Client side.  Given a valid username and password, obtain a cookie.

Returns C<($status, $failed, $detail)>.  $failed is a brief
explanation of the problem, or false on success.  $detail is the full
body of the reply.

Successful login modifies the cookie jar of $fetcher, to enable later
authenticated requests.

=cut

sub login {
    my ($called, $fetcher, $user, $password) = @_;

    # need to url-encode these
    $user     = uri_escape($user);      # possibly not worth it...
    $password = uri_escape($password);  # definitely worth it!

    my $req = HTTP::Request->new;
    $req->method('POST');
    $req->uri("https://enigma.sanger.ac.uk/LOGIN");
    $req->content_type('application/x-www-form-urlencoded');
    $req->content("credential_0=$user&credential_1=$password&destination=/");

    my $response = $fetcher->request($req);
    my $content = $response->decoded_content;
    my $failed;

    if ($response->is_success) {
        $failed = '';
    } else {
        # log the detail - content may be large
        my $msg = sprintf("Authentication as %s failed: %s\n",
                          $user, $response->status_line);
        if ($content =~ m{<title>Sanger Single Sign-on login}) {
            # Some common special cases
            if ($content =~ m{<P>(Invalid account details\. Please try again|Please enter your login and password to authenticate)</P>}i) {
                $msg = "Login failed: $1";
            } elsif ($content =~
                     m{The account <b>(.*)</b> has been temporarily locked}) {
                $msg = "Login failed and account $1 is now temporarily locked.";
                $msg .= "\nPlease wait $1 and try again, or contact Anacode for support"
                  if $content =~ m{Please try again in ((\d+ hours?)?,? \d+ minutes?)};
            } # else probably an entire HTML page
        }

        $failed = $msg;
    }
    return ($response->status_line, $failed, $content);
}


=head2 auth_user($sangerweb, $external_users_hash)

Server side.  Given an existing L<SangerWeb> object containing the
client's authentication cookie, and a hash of external users, set
flags for the user.

Returns a list of hash key => value pairs suitable for inserting into
L<Bio::Otter::ServerScriptSupport> objects,

=over 4

=item _authorized_user

The username, or C<undef> if none.

=item _internal_user

True iff the user is authorised and "internal", i.e. a member of staff
or visiting worker.

=back

Note that this rolls authentication and authorisation into one lump.

=cut

sub auth_user {
    my ($called, $sangerweb, $users_hash) = @_;
    my %out = (_authorized_user => undef, _internal_user => 0);

    $out{_local_user} = ($ENV{'HTTP_CLIENTREALM'} =~ /sanger/ ? 1 : 0);
    # ...from the HTTP header added by front end proxy

    if (my $user = lc($sangerweb->username)) {
        my $auth_flag     = 0;
        my $internal_flag = 0;

        if ($user =~ /^[a-z0-9]+$/) {   # Internal users (simple user name)
            $auth_flag = 1;
            $internal_flag = 1;
        } elsif ($users_hash->{$user}) {  # Check external users (email address)
            $auth_flag = 1;
        } # else not auth

        if ($auth_flag) {
            $out{'_authorized_user'} = $user;
            $out{'_internal_user'}   = $internal_flag;
        }
    }

    die 'wantarray!' unless wantarray;
    return %out;
}


=head2 test_key()

Return the name of the key output by L<scripts/apache/test> which
exposes cookie interpretation.

=cut

sub test_key {
    return 'B:O:Auth::SSO';
}


1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut
