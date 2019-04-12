#!/usr/bin/perl

use 5.010;
use warnings;
use strict;
use utf8;
use Carp;
use Encode qw(encode decode);

use FindBin;
use lib "$FindBin::Bin/";

use File::Slurp qw(read_file write_file);
use Digest::MD5 qw(md5_hex);

use AG::Config;
use AG::Categories;

use MyLaTeXParser;
use MyLaTeXPrinter;
use MyLaTeX;

no if $] >= 5.018, warnings => "experimental::smartmatch";

sub msg {
    my $caller = ( caller 1 )[3] // '[no_caller]';

    print "$caller(): @_\n";
    return;
}

{
    my $images_dpi = 200;

    sub pdf_of_png {
        my $global = shift;
        my $svg    = shift;

        my $q_dpi   = quotemeta $images_dpi;
        my $q_svg   = quotemeta $svg;
        my $command = "inkscape -D -d $q_dpi -z $q_svg -e ";
        my $png     = "$global->{config}{destination_directory}/" . ( md5_hex $command) . ".png";
        if ( ! -e $png || ( stat $png )[9] < ( stat $svg )[9] ) {
            system $command . quotemeta $png;
        }

        return $png;
    }
}

binmode STDOUT, ':encoding(utf-8)';

my $global = AG::Config::init();

if ( ! -e $global->{config}{destination_directory} && ! mkdir $global->{config}{destination_directory} ) {
    croak "Cannot create destination direcotry: $!";
}

my %commands_map;

my @tex_route_lists;
while ( my ( $lname, $list ) = each %{ $global->{config}{lists} } ) {
    my @list_routes = grep {
        ( $list->{routes_filter} // sub {1} )->($_)
    } @{ $global->{routes} };

    my $route_template = decode( 'utf-8', read_file("$global->{config}{template_directory}/$list->{route_template}") );

    my $content = q{};
    foreach my $route (@list_routes) {
        my $description = decode( 'utf-8', read_file("$route->{path}/description.tex") );
        $description = MyLaTeXParser::parse( id => "$route->{path}/description.tex", document => $description );

        my $category = AG::Categories::get( $global, $route->{category} );
        my $peaks = join q{, }, @{ $route->{peak} };

        my $uiaa = q{};
        if ( -f "$route->{path}/uiaa.svg" ) {
            $uiaa = pdf_of_png( $global, "$route->{path}/uiaa.svg" );
        }

        my $region = $global->{regions}{ $route->{region} };

        my $geopoints_mapper = sub {
            my $command = shift;

            if ( my ($geoname) = $command->{command} =~ m{^geo(.+)} ) {
                if ( exists $region->{geopoints}{$geoname} ) {
                    my $point = $region->{geopoints}{$geoname};
                    my $name  = $point->{name};
                    if ( defined $command->{args} && @{ $command->{args} } && @{ $command->{args}[0]{content} } ) {
                        $name = MyLaTeXPrinter::latex( document => $command->{args}[0]{content} );
                    }
                    return 1,
                        MyLaTeX::command(
                        command => 'geopoint',
                        args    => [
                            { type => 'brace', content => [ MyLaTeX::text( sprintf '%.7f', $point->{latitude} ) ], },
                            { type => 'brace', content => [ MyLaTeX::text( sprintf '%.7f', $point->{longtitude} ) ], },
                            { type => 'brace', content => [ MyLaTeX::text( $point->{altitude} // q{} ) ], },
                            { type => 'brace', content => [ MyLaTeX::text($name) ], },
                        ] );
                }
            }

            return 0;
        };

        my $mapper = sub {
            my $doc = shift;

            return MyLaTeX::map_commands(
                list => $doc,
                map  => {
                    routeTitle       => sub { MyLaTeX::text( $route->{title} ) },
                    routePeak        => sub { MyLaTeX::text($peaks) },
                    routeCategory    => sub { MyLaTeX::text($category) },
                    routeType        => sub { MyLaTeX::text( $route->{type} ) },
                    routeName        => sub { MyLaTeX::text( $route->{name} ) },
                    routeRegionName  => sub { MyLaTeX::text( $region->{name} ) },
                    routeEquipment   => sub { MyLaTeX::text( $route->{equipment} ) },
                    routeAuthors     => sub { MyLaTeX::text( join q{, }, sort @{ $route->{authors} } ) },
                    routeDescription => sub { MyLaTeX::text($description) },
                    routeUIAAPath    => sub { MyLaTeX::text($uiaa) },
                },
                unified => $geopoints_mapper
            );
        };

        $description = $mapper->($description);
        $description = MyLaTeXPrinter::latex( document => $description );

        my $doc = $route_template;

        $doc = MyLaTeXParser::parse( id => "List $lname, route '$route->{title}'", document => $doc );
        $doc = $mapper->($doc);

        $content .= MyLaTeXPrinter::latex( document => $doc );
    }

    my $doc = MyLaTeXParser::parse( id => "List $lname", document => $content, error_context => 1000 );
    $commands_map{$lname} = sub { return @{$doc} };
    push @tex_route_lists, "\\newcommand{\\routeList$lname}[0]{$content}\n";
}

my $book = read_file( "$global->{config}{template_directory}/book.tex", binmode => ':utf8' );
$book = MyLaTeXParser::parse( document => $book );
$book = MyLaTeX::map_commands(
    list => $book,
    map  => \%commands_map
);

system "cd " . ( quotemeta $global->{config}{destination_directory} ) . "; rm -f book.*";

write_file( "$global->{config}{destination_directory}/book.tex", encode( 'utf-8', MyLaTeXPrinter::latex( document => $book ) ) );

system "cd "
    . ( quotemeta $global->{config}{destination_directory} )
    . "; makeglossaries book.glo; pdflatex -halt-on-error -file-line-error book.tex && pdflatex -halt-on-error -file-line-error book.tex";
