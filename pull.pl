#!/usr/bin/perl -w

use v5.10;
use strict;
use warnings;

use Getopt::Long;
use LWP::UserAgent;
use Try::Tiny;
use File::Temp;
use Pod::Usage;

# Command line options? We expect a URL to either:
#   1. A journal issue to extract data from.
#   2. The article containing the nomenclatural changes.
#   3. The table to extract data from.
my $help =  0;
my $man =   0;

my $url = "http://ijs.sgmjournals.org/content/current";
my $result = GetOptions(
    "url=s" =>      \$url,
    "help|?" =>     \$help,
    "man" =>        \$man
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Okay, go time!
say "Downloading content from $url ...";
my $content = download_page($url);

# What is it, then?
given($content) {
    default {
        say "Sorry, unable to identify content at $url.";

        my $tmp = File::Temp->new();
        binmode $tmp, ":utf8";
        say $tmp $content;
        close $tmp;

        say "Website content was stored in file '" . $tmp->filename . "' for perusal.";
    }
}

# Download a page.
sub download_page {
    my $url = shift;
    my $lwp = LWP::UserAgent->new();

    my $response = $lwp->get($url);
    my $content = $response->decoded_content;

    unless($response->is_success()) {
        use Data::Dumper;
        die "Error connecting to $url: " . Dumper($response);
    }

    return $content;
}

