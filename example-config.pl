{   destination_directory => '/tmp/guidebook',
    category_system       => 'russian',
    template_directory    => 'templates/template1',
    lists                 => {
        routeListEasyAlaArcha => {
            routes_filter => sub {
                $_->{region} eq 'ala-archa' && $_->{category} le '3Б';
            },
            route_template => 'route-template1.tex',
        },
        routeListMiddleAlaArcha => {
            routes_filter => sub {
                $_->{region} eq 'ala-archa' && $_->{category} gt '3Б' && $_->{category} lt '5Б';
            },
            route_template => 'route-template1.tex',
        },
        routeListOther => {
            routes_filter => sub {
                $_->{region} ne 'ala-archa';
            },
            route_template => 'route-template1.tex',
        },
    } }
