package mafia;

use strict;
use warnings;
no warnings 'redefine', 'qw';
use sort 'stable';
use Carp qw(cluck);
use Storable;


our (%player_ratings, %setup_ratings);
our %player_accounts;
our @top_players;
our %top_players;
our $loaded_ratings;
our $loaded_ratings2;
our %player_data; 
our $mafiachannel;
our $cur_setup;
our %group_data;
our (%player_masks, %players_by_mask);
our %starting_groups;
our @players;
our $ratingsfile = "mafia/player-ratings";
our $setupratingsfile = "mafia/setup-ratings";

our %sortfields = (
rating => 1,
wins => 1,
games => 1,
losses => 1,
draws => 1,
change =>1,
lastseen => 1 
);

our $factor = 36;
our $divisor = 400;
our $debugstats = 1;

our %valid_setups = (
"#mafia" => 0,
assassin => 0,
australian => 1,
average => 1,
balanced => 1,
basic12 => 0,
bonanza => 1,
c9 => 0,
chainsaw => 0,
challenge => 1,
chaos => 1,
chosen => 1,
cocopotato => 0,
cosmic => 1,
"cosmic-smalltown" => 1,
deepsouth => 0,
deliciouscake => 1,
dethy => 0,
dethy11 => 0,
dethy7 => 0,
evomomir => 0,
eyewitness => 0,
f11 => 0,
faction => 0,
fadebot => 1,
ff6 => 1,
gunfight => 0,
"gunfight-chosen" => 0,
"gunfight-insane" => 0,
insane => 1,
kingmaker => 0,
kingmaker2 => 0,
league => 1,
luigi => 1,
lynchem => 0,
martian => 1,
mc9 => 0,
mild => 1,
mixed => 1,
mm => 1,
moderated => 0,
momir => 0,
"momir-duel" => 0,
mountainous => 1,
multichosen => 1,
multirole => 1,
"neko-open" => 0,
noreveal => 1,
normal => 1,
oddrole => 1,
outfox => 1,
piec9 => 0,
raf => 0,
rps => 0,
screwball => 0,
simenon => 0,
smalltown => 1,
"smalltown+" => 1,
"smalltown+-base" => 0,
ss3 => 0,
straight => 1,
test => 0,
texas10 => 0,
timespiral => 1,
tornado => 1,
unranked => 0,
upick => 0,
vengeful => 0,
wacky => 1,
wtf => 0,
xany => 0,
xylspecial => 1
);

#default player ratings
our ($drating) = 1600;

retrieve_ratings();

sub import_ratings {
	if ( -e $ratingsfile) {
		$loaded_ratings = retrieve($ratingsfile) or die $!;	
	}
	if ( ( -e $ratingsfile) && (defined $ratingsfile) ) {
		$loaded_ratings = retrieve($ratingsfile) or die $!;
		%player_ratings = %{ $loaded_ratings };
		::bot_log "Ratings loaded from $ratingsfile \n";
	}
	elsif ( !(-e $ratingsfile)) {
		::bot_log "$ratingsfile does not exist.\n";
	}
	if ( ( -e $setupratingsfile) && (defined $setupratingsfile) ) {
		$loaded_ratings2 = retrieve($setupratingsfile) or die $!;
		%player_ratings = %{ $loaded_ratings2 };
		::bot_log "Ratings loaded from $setupratingsfile \n";
	}
	elsif ( !(-e $ratingsfile)) {
		::bot_log "$ratingsfile does not exist.\n";
	}
}

sub export_ratings {
	my $rank = 1;
	foreach my $key (keys %top_players) {
		delete $top_players{$key};
	}
	
	%player_accounts = ();
	@top_players = ();

	foreach my $group (keys %starting_groups) {
		delete $starting_groups{$group};
	}

	store(\%player_ratings, $ratingsfile);
	store(\%setup_ratings, $setupratingsfile);
	store_ratings();
}

sub sort_awesome {
	my ($setup, $sortby, $direction) = @_;
	my $sortname = $direction."_".$setup."_".$sortby;

	return 0 unless $sortfields{$sortby};	

	return @{ $top_players{$sortname} } if defined @{ $top_players{$sortname} };

	if ($setup eq 'rated') {
		if (lc($direction) eq 'bottom') {
			$top_players{$sortname} = [ sort { $player_ratings{$a}{$sortby} <=> $player_ratings{$b}{$sortby} } keys %player_ratings ];
		}
		elsif (lc($direction) eq 'top') {
			$top_players{$sortname} = [ reverse sort { $player_ratings{$a}{$sortby} <=> $player_ratings{$b}{$sortby} } keys %player_ratings ];
		}
	}
	else {
		if (lc($direction) eq 'bottom') {
			$top_players{$sortname} = [ sort { $setup_ratings{$setup}{$a}{$sortby} <=> $setup_ratings{$setup}{$b}{$sortby} } keys %{ $setup_ratings{$setup} } ];
		}
		elsif (lc($direction) eq 'top') {
			$top_players{$sortname} = [ reverse sort { $setup_ratings{$setup}{$a}{$sortby} <=> $setup_ratings{$setup}{$b}{$sortby} } keys %{ $setup_ratings{$setup} } ];
		}

	}

	return @{ $top_players{$sortname} };
	
}


# No variables are passed to this, but the @players variable needs to be populated
# With the player data before calling this
sub calculate_draw {
	my %results = @_;

	my $setup = $cur_setup->{setup};

	if ($setup eq 'test' || $setup eq 'moderated' || $setup eq 'upick') {
		::bot_log "RATINGS Disabled for $setup\n";
		return 0;
	}

	foreach my $player (@players)
	{
		$results{$player} = 0.5;
	}
	calculate_ratings(%results);
}

# only argument is the %winners table that is determined by the game_over function in module.pm
# Requires the $cur_setup, @players, @player_data, and @player_accounts to be populated in memory before calling it.
sub calculate_ratings {
	my (%results) = @_;
	my $setup = $cur_setup->{setup};
	if ($setup eq 'test' || $setup eq 'moderated' || $setup eq 'upick') {
		::bot_log "RATINGS Disabled for $setup\n";
		return 0;
	}

	%top_players = ();
	
	foreach my $player (@players)
	{
		::bot_log "RATINGS FOR $player\n";
		my $account = $player_accounts{$player};
		$results{$player} = 0 unless $results{$player} > 0 ;
		my $playerteam = get_player_team_short($player);
		::bot_log "PLAYERTEAM $playerteam\n";
		my $endtime = time;
		my $newrating;
		if ($account && $account ne 'nologin' && $account ne 'fake') {
			
			$player_ratings{$account}{'lastsetup'} = $setup;

			setup_rating($player, $playerteam, %results);	#player rating for team
			setup_rating($player, $setup, %results);	#player rating for setup
			setup_rating($player, 'all', %results);		#player rating for all

			if ($valid_setups{$setup}) {
				my $newrating = setup_rating($player, 'rated', %results);
				::bot_log "RATINGS: $player ($account) ratedsetup $newrating\n";
			}
			else {
				::bot_log "RATINGS: $player ($account) $setup is unrated\n";
			}
		}
		else {
			::bot_log "RATINGS: $player is not eligible to be rated\n";
		}
	}
	export_ratings();
}

# Only call this at the beginning of the game or you will be calculating ratings after people have had a chance to change teams/be recruited
# Everywhere else assumes that these teams are the same as the $player_data{$player}{startteam} reference.
sub begin_stats {
	my $setup = $cur_setup->{setup};

	if ($setup eq 'test' || $setup eq 'moderated' || $setup eq 'upick') {
		::bot_log "RATINGS Disabled for $setup\n";
		return 0;
	}

	foreach my $group (keys %group_data)
	{
		my @group_results = group_rating($group);
		$group_data{$group}{'rating'} = shift @group_results;
		$group_data{$group}{'setuprating'} = shift @group_results;
		$group_data{$group}{'allrating'} = shift @group_results;
		
	}
	foreach my $player (@players) {	
		$player_accounts{$player} = get_player_account($player);
	}
}

sub cancel_stats {
	foreach my $group (keys %starting_groups) {
		delete $starting_groups{$group};
	}
}


# This must be called for each group that exists at the beginning of the game.
sub group_rating {
	my $group = shift @_;	
	my $grouprating = 0;
	my $setuprating = 0;
	my $allrating = 0;
	my @members = get_group_members($group);
	my $totalmembers = 0;
	my $setup = $cur_setup->{setup};

	$starting_groups{$group}++;
	
	foreach my $member (@members)
	{
		$member = get_player_account($member);
		$grouprating += get_player_rating($member);
		$setuprating += get_setup_rating($member, $setup);
		$allrating += get_setup_rating($member, 'all');	
		$totalmembers++;
	}		
	
	$setuprating /= $totalmembers;
	$allrating /= $totalmembers;
	$grouprating /= $totalmembers;
	::bot_log "RATINGS: $group: $grouprating | $setup: $setuprating | all: $allrating | Average of @members \n";
	return ($grouprating, $setuprating, $allrating);
}

sub get_player_account {
	my $player = shift @_;	
	my $account = ::get_account($player);
	return $account;
}

sub get_setup_rating {
	my ($player) = shift @_;
	my ($setup) = shift @_;
	my $rating;
	if ($player eq 'fake'||$player eq 'nologin') {
		$rating = $drating
	}
	elsif (exists $setup_ratings{$setup}{$player}{'rating'}) {
		$rating = $setup_ratings{$setup}{$player}{'rating'};
		::bot_log "$player has a rating of $rating for $setup\n" if $debugstats;
	}
	else {
		$rating = $drating;
		::bot_log "$player has played no games of $setup and is rated at $rating\n" if $debugstats;
	}
	return $rating;
}

sub get_setup_stats {
	my ($player, $setup) = @_;
	my $rating;
	
	if ($player eq 'fake' || $player eq 'nologin') {
		return 0;
	}
	elsif (exists $setup_ratings{$setup}{$player}{rating}) {
		my @stats;
		push @stats, $setup_ratings{$setup}{$player}{rating};
		push @stats, $player_ratings{$player}{alias};
		push @stats, $setup_ratings{$setup}{$player}{games};
		push @stats, $setup_ratings{$setup}{$player}{wins};
		push @stats, $setup_ratings{$setup}{$player}{losses};
		push @stats, $setup_ratings{$setup}{$player}{draws};
		push @stats, $setup_ratings{$setup}{$player}{change};
		push @stats, (time - $setup_ratings{$setup}{$player}{lastseen});
		return @stats;
	}
}

sub get_player_stats {
	my ($player) = shift @_;
	my $rating;
	if ($player eq 'fake' || $player eq 'nologin') {
    		return 0;
	}
	elsif (exists $player_ratings{$player}{'rating'}) {
		my @stats;
		push @stats, $player_ratings{$player}{rating};
		push @stats, $player_ratings{$player}{alias};
		push @stats, $player_ratings{$player}{games};
		push @stats, $player_ratings{$player}{wins};
		push @stats, $player_ratings{$player}{losses};
		push @stats, $player_ratings{$player}{draws};
		push @stats, $player_ratings{$player}{change};
		push @stats, (time - $player_ratings{$player}{lastseen});
		push @stats, $player_ratings{$player}{lastsetup};
		return (@stats);
	}
	else {
		return 0;
	}
}
	
sub get_player_rating {
	my ($player) = shift @_;
	my $rating;
	if ($player eq 'fake' || $player eq 'nologin') {
    		$rating = $drating
	}
	elsif (exists $player_ratings{$player}{'rating'}) {
		$rating = $player_ratings{$player}{'rating'};
		::bot_log "$player has a rating of $rating\n" if $debugstats;
	}
	else {
		$rating = $drating;
		::bot_log "$player has played no rated games and is rated at $rating\n" if $debugstats;
	}
	return $rating;
}

sub set_rating {
	my ($player, $newrating) = @_;
	if ($newrating == 0) {return 0;}
	elsif (exists $player_ratings{$player}{'games'}) {
		$player_ratings{$player}{rating} = $newrating;
	}
	elsif ($newrating) {
		$player_ratings{$player}{'rating'} = $newrating;
		$player_ratings{$player}{'alias'} = $player;
		$player_ratings{$player}{'wins'} = 0;
		$player_ratings{$player}{'games'} = 0;
		$player_ratings{$player}{'draws'} = 0;
		$player_ratings{$player}{'losses'} = 0;
		$player_ratings{$player}{'change'} = 0;
		$player_ratings{$player}{'lastsetup'} = 'none';
		$player_ratings{$player}{'lastseen'} = 0;
	}
}

sub setup_rating {
	my ($player, $setup, %results) = @_;

	return 0 if ($player_accounts{$player} eq 'fake' || $player_accounts{$player} eq 'nologin');

	my $average = 0;
	my $account = $player_accounts{$player};
	my $startteam = $player_data{$player}{'startteam'};
	my $playerrating;
	my $rating = $group_data{$startteam}{'setuprating'};
	my $groupcount = 0;
	my $result = $results{$player};
	my $endtime = time;

	my $ratingsetup;


	if ($setup eq 'rated') {
		$ratingsetup = 'rating';
		$playerrating = get_player_rating($account);
		$rating = $group_data{$startteam}{'rating'};
		$player_ratings{$account}{'wins'} = 0 unless exists $player_ratings{$account}{'wins'};
		$player_ratings{$account}{'draws'} = 0 unless exists $player_ratings{$account}{'draws'};
		$player_ratings{$account}{'losses'} = 0 unless exists $player_ratings{$account}{'losses'};
	}
	else {
		$ratingsetup = 'setuprating';
		if ($setup eq 'all') {
			$ratingsetup = 'allrating';
			$rating = $group_data{$startteam}{'allrating'};
		}
		$playerrating = get_setup_rating($account, $setup);
		$setup_ratings{$setup}{$account}{'rating'} = $drating unless exists $setup_ratings{$setup}{$account}{'rating'};
		$setup_ratings{$setup}{$account}{'wins'} = 0 unless exists $setup_ratings{$setup}{$account}{'wins'};
		$setup_ratings{$setup}{$account}{'draws'} = 0 unless exists $setup_ratings{$setup}{$account}{'draws'};
		$setup_ratings{$setup}{$account}{'losses'} = 0 unless exists $setup_ratings{$setup}{$account}{'losses'};
	}

	::bot_log "RATINGS: ".$player."'s team rating is: $rating for $setup \n" if $debugstats;

	foreach my $group (keys %starting_groups)
	{
		if ($startteam ne $group && $group ne 'survivor') 
		{
			my @elo_results = elo($rating, $result, $group_data{$group}{$ratingsetup});
			$average += $elo_results[0];
			::bot_log "ELO: $rating, $result, $group, $group_data{$group}{$ratingsetup}: $elo_results[0] \n" if $debugstats;
			$groupcount += 1;
		}
	}
	$average /= $groupcount;

	$average = ($playerrating + ($average - $rating));
	if ($setup eq 'rated') {
		$player_ratings{$account}{'rating'} = $average;
		if ($result == 1) {
			$player_ratings{$account}{'wins'}++;
		}
		elsif ($result == 0.5) { 
			$player_ratings{$account}{'draws'}++;
		}
		elsif (!$result) {
			$player_ratings{$account}{'losses'}++; 
		}
		$player_ratings{$account}{'games'}++;
		
	}
	else {
			
		if ($result == 1) {
			$setup_ratings{$setup}{$account}{'wins'}++;
		}
		elsif ($result == 0.5) {
			$setup_ratings{$setup}{$account}{'draws'}++; 
		}
		elsif (!$result) {
			$setup_ratings{$setup}{$account}{'losses'}++;
		}
	
		$setup_ratings{$setup}{$account}{rating} = $average;

		$setup_ratings{$setup}{$account}{'lastseen'} = $endtime;
		$setup_ratings{$setup}{$account}{'games'}++;
		$setup_ratings{$setup}{$account}{'change'} = ($average - $playerrating);
		$player_ratings{$account}{'change'} = ($average - $playerrating);

	}
	
	$player_ratings{$account}{'rating'} = $drating unless exists $player_ratings{$account}{'rating'};
	$player_ratings{$account}{'games'} = 0 unless exists $player_ratings{$account}{'games'};
	$player_ratings{$account}{'wins'} = 0 unless exists $player_ratings{$account}{'wins'};
	$player_ratings{$account}{'draws'} = 0 unless exists $player_ratings{$account}{'draws'};
	$player_ratings{$account}{'losses'} = 0 unless exists $player_ratings{$account}{'losses'};

	$player_ratings{$account}{'alias'} = $player;
	$player_ratings{$account}{'lastseen'} = $endtime;


	::bot_log "RATINGS $player ($account) Setup: $setup Old: $playerrating New: $average \n" if $debugstats;
	return $average;
}

sub elo {
	my @results;
	my ($A, $result, $B) = @_;

	my $Aexp = 10 ** ( ($B - $A) / $divisor ) ;
  

	my $A2 = 
		$A + $factor * ( $result - 
		     ( 1 / 
		       ( 1 + $Aexp )
		     )
		   )
	      ;

	my $Bexp = 10 ** ( ($A - $B) / $divisor ) ;
  
	$result = 1 - $result;

	my $B2 = 
		$B + $factor * ( $result - 
		     ( 1 / 
		       ( 1 + $Bexp )
		     )
		   )
	      ;
	return ($A2, $B2);
}

## Beginning work on saving player stats in plaintext.

sub store_ratings {
	::bot_log "Error while opening ratings file mafia/ratings.temp $! \n" unless open RATINGS, '>', 'mafia/ratings.temp' or die $!;

	foreach my $player (sort {$player_ratings{$a}{rating} <=> $player_ratings{$b}{rating} } keys %player_ratings) {
		my ($alias, $rating, $games, $wins, $losses, $draws, $change, $lastsetup, $lastseen);
		$alias = $player_ratings{$player}{alias};
		$rating = $player_ratings{$player}{rating};
		$games = $player_ratings{$player}{games};
		$wins = $player_ratings{$player}{wins};
		$losses = $player_ratings{$player}{losses};
		$draws = $player_ratings{$player}{draws};
		$change = $player_ratings{$player}{change};
		$lastsetup = $player_ratings{$player}{lastsetup};
		$lastseen = $player_ratings{$player}{lastseen};
		#::bot_log "($player, $alias, $rating, $games, $wins, $losses, $draws, $change, $lastsetup, $lastseen)\n";
		print RATINGS "$player $alias $rating $games $wins $losses $draws $change $lastsetup $lastseen\n";
	}
	print RATINGS "SETUPS\n";
	foreach my $setup (sort keys %setup_ratings) {
		foreach my $player (sort { $setup_ratings{$setup}{$a}{rating} <=> $setup_ratings{$setup}{$b}{rating} } keys %{ $setup_ratings{$setup} }) {
			my ($rating, $games, $wins, $losses, $draws, $change, $lastseen);
			$rating = $setup_ratings{$setup}{$player}{rating};
			$games = $setup_ratings{$setup}{$player}{games};
			$wins = $setup_ratings{$setup}{$player}{wins};
			$losses = $setup_ratings{$setup}{$player}{losses};
			$draws = $setup_ratings{$setup}{$player}{draws};
			$change = $setup_ratings{$setup}{$player}{change};
			$lastseen = $setup_ratings{$setup}{$player}{lastseen};
			#::bot_log "($setup, $player, $rating, $games, $wins, $losses, $draws, $change, $lastseen)\n";
			print RATINGS "$setup $player $rating $games $wins $losses $draws $change $lastseen\n";
		}
	}
	
	
	my $templocation = "ratings.temp";
	my $newlocation = "ratings.dat";
	::bot_log "Failed to move ratings.temp to ratings.dat $! \n" unless move ($templocation, $newlocation) or die $!;
	
	close(RATINGS);
	
	
	
}

sub retrieve_ratings {
	my $result;
	if ( -e "mafia/ratings.dat" ) {
		unless (open RATINGS, "<", "mafia/ratings.dat" or die $!) {
			::bot_log "Error while loading ratings from mafia/ratings.dat $! \n";
		}
	}
	else {
		::bot_log "Could not load ratings from \"mafia/ratings.dat\": file not found.\n";
		return 1;
	}

	

	my $setupsection = 0;

	while (<RATINGS>) {
		chomp;
		s/\t/ /;				# tabs have no business being in this file
    		s/^\s+//;				# no leading white
    		s/\s+$//;				# no trailing white
		
		::bot_log "$_\n" if $debugstats;

		if ( $_ eq 'SETUPS' ) {
			$setupsection = 1;
			::bot_log "RETRIEVE SETUP SECTION\n" if $debugstats;
		}
		elsif ($setupsection) {
			my ($setup, $player, $rating, $games, $wins, $losses, $draws, $change, $lastseen) = split /\s/, $_;
			$setup_ratings{$setup}{$player}{rating} = $rating;
			$setup_ratings{$setup}{$player}{games} = $games;
			$setup_ratings{$setup}{$player}{wins} = $wins;
			$setup_ratings{$setup}{$player}{losses} = $losses;
			$setup_ratings{$setup}{$player}{draws} = $draws;
			$setup_ratings{$setup}{$player}{change} = $change;
			$setup_ratings{$setup}{$player}{lastseen} = $lastseen;
		}
		else {		
			my ($player, $alias, $rating, $games, $wins, $losses, $draws, $change, $lastsetup, $lastseen) = split /\s/, $_;	
			$player_ratings{$player}{alias} = $alias;
			$player_ratings{$player}{rating} = $rating;
			$player_ratings{$player}{games} = $games;
			$player_ratings{$player}{wins} = $wins;
			$player_ratings{$player}{losses} = $losses;
			$player_ratings{$player}{draws} = $draws;
			$player_ratings{$player}{change} = $change;
			$player_ratings{$player}{lastsetup} = $lastsetup;
			$player_ratings{$player}{lastseen} = $lastseen;
		}
	}
	close(RATINGS);
}
