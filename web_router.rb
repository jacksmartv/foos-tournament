$LOAD_PATH << '.'

require 'sinatra'
require 'tilt/erb'

require 'season_repository'
require 'division_repository'
require 'match_repository'
require 'player_repository'
require 'result_processor'
require 'json'

get '/' do
  season_repo = SeasonRepository.new()
  @seasons = season_repo.get_all_seasons()
  current_season = season_repo.get_most_recent_season()
  @default_season_id = current_season.id
  @default_season_title = current_season.title
  erb :web
end

get '/ajax/season/:season_id' do
  season_id = params[:season_id].to_i
  season_repo = SeasonRepository.new()
  season = season_repo.get(season_id)
  @divisions = season.divisions
  erb :season
end

get '/ajax/summary/:season_id' do
  season_repo = SeasonRepository.new()
  division_repo = DivisionRepository.new()
  season = season_repo.get(params[:season_id].to_i)
  divisions = season.divisions
  @division_data = {}
  divisions.each do |d|
    division_entity = division_repo.get(d.id)
    @division_data[d.id] = {
      :name => division_entity.name,
      :classification => division_entity.get_classification()
    }
  end

  match_repo = MatchRepository.new()
  division_ids = @division_data.keys()
  @recent_matches = match_repo.get_recently_finished_matches(division_ids, 8)

  player_repo = PlayerRepository.new
  @players = player_repo.get_all_players_by_id()

  erb :summary
end

get '/ajax/division/:division' do
  division_repo = DivisionRepository.new
  division = division_repo.get(params[:division].to_i)
  @classification = division.get_classification()
  @rivals = division.get_rivals_info()
  @open_matches = division.get_open_matches()
  @finished_matches = division.get_finished_matches()

  player_repo = PlayerRepository.new
  @players = player_repo.get_all_players_by_id()

  erb :division
end

get '/ajax/simulator/:match' do
  @match_id = params[:match].to_i
  match_repo = MatchRepository.new()
  match = match_repo.get(@match_id)

  division_repo = DivisionRepository.new()
  division = division_repo.get(match.division_id)

  player_repo = PlayerRepository.new
  @players = player_repo.get_all_players_by_id()

  @match_players = match.players
  match_player_names = @match_players.map { |x| @players[x].name }

  @classification = division.get_classification()
  @classification.each do |c|
    if @match_players.include?(c[:player_id])
      c[:highlight] = true
    else
      c[:highlight] = false
    end
  end

  @results1 = [[5, 0], [5, 1], [5, 2], [5, 3], [5, 4]]
  @results2 = [[4, 5], [3, 5], [2, 5], [1, 5], [0, 5]]

  @submatches = [
    {
      :idx => 1,
      :player1a => match_player_names[0],
      :player1b => match_player_names[1],
      :player2a => match_player_names[2],
      :player2b => match_player_names[3],
    },
    {
      :idx => 2,
      :player1a => match_player_names[0],
      :player1b => match_player_names[2],
      :player2a => match_player_names[1],
      :player2b => match_player_names[3],
    },
    {
      :idx => 3,
      :player1a => match_player_names[0],
      :player1b => match_player_names[3],
      :player2a => match_player_names[1],
      :player2b => match_player_names[2],
    }
  ]

  erb :simulator
end

post '/ajax/simulation/:match' do
  body = request.body.read
  data = JSON.parse(body)

  match_id = params[:match].to_i
  match_repo = MatchRepository.new()
  match = match_repo.get(match_id)
  match.set_played_status(true, Time.now.to_i, 0)
  match.set_scores(data['results'])

  division_repo = DivisionRepository.new()
  division = division_repo.get(match.division_id)

  player_repo = PlayerRepository.new()
  @players = player_repo.get_all_players_by_id()

  @classification = division.get_classification_with_extra_match(match)
  match_players = match.players
  @classification.each do |c|
    if match_players.include?(c[:player_id])
      c[:highlight] = true
    else
      c[:highlight] = false
    end
  end

  erb :simulation
end

get %r{/api/v1/players/?$} do
  player_repo = PlayerRepository.new()
  response = {}
  player_repo.get_all_players().each do |p|
    response[p.id] = player2api(p)
  end
  return JSON.generate(response)
end

get %r{/api/v1/players/(?<player_id>\d+)/?$} do
  player_repo = PlayerRepository.new()
  p = player_repo.get(params[:player_id])
  return JSON.generate(player2api(p))
end

get %r{/api/v1/seasons/?$} do
  season_repo = SeasonRepository.new()
  response = []
  season_repo.get_all_seasons().each do |s|
    response << season2api(s)
  end
  return JSON.generate(response)
end

get %r{/api/v1/seasons/current/?$} do
  season_repo = SeasonRepository.new()
  s = season_repo.get_most_recent_season()
  return JSON.generate(season2api(s))
end

get %r{/api/v1/seasons/(?<season_id>\d+)/?$} do
  season_repo = SeasonRepository.new()
  s = season_repo.get(params[:season_id].to_i)
  return JSON.generate(season2api(s))
end

get %r{/api/v1/divisions/(?<division_id>\d+)/?$} do
  division_repo = DivisionRepository.new()
  d = division_repo.get(params[:division_id].to_i)
  return JSON.generate(division2api(d))
end

get %r{/api/v1/divisions/(?<division_id>\d+)/players/?$} do
  division_repo = DivisionRepository.new()
  d = division_repo.get(params[:division_id].to_i)
  response = {}
  d.players.each do |p|
    response[p.id] = player2api(p)
  end
  return JSON.generate(response)
end

get %r{/api/v1/divisions/(?<division_id>\d+)/players/(?<player_id>\d+)/?$} do
  response = {}
  division_repo = DivisionRepository.new()
  d = division_repo.get(params[:division_id].to_i)
  if d
    p = d.players.find { |x| x.id == params[:player_id].to_i }
    if p
      if d.absences.key?(p.id)
        absences = d.absences[p.id]
      else
        absences = []
      end
      response = player2api(p)
      response['absences'] = absences
    end
  end
  return JSON.generate(response)
end

get %r{/api/v1/divisions/(?<division_id>\d+)/matches/?$} do
  division_repo = DivisionRepository.new()
  d = division_repo.get(params[:division_id].to_i)
  response = []
  open_matches = d.get_all_matches()
  open_matches.each do |m|
    response << match2api(m)
  end

  JSON.generate(response)
end

get %r{/api/v1/divisions/(?<division_id>\d+)/matches/open/?$} do
  division_repo = DivisionRepository.new()
  d = division_repo.get(params[:division_id].to_i)

  response = []
  open_matches = d.get_open_matches()
  open_matches.each do |m|
    response << match2api(m)
  end

  JSON.generate(response)
end

get %r{/api/v1/divisions/(?<division_id>\d+)/matches/played/?$} do
  division_repo = DivisionRepository.new()
  d = division_repo.get(params[:division_id].to_i)

  response = []
  open_matches = d.get_finished_matches()
  open_matches.each do |m|
    response << match2api(m)
  end

  JSON.generate(response)
end

get %r{/api/v1/divisions/(?<division_id>\d+)/classification/?$} do
  division_repo = DivisionRepository.new()
  d = division_repo.get(params[:division_id].to_i)
  response = d.get_classification()

  JSON.generate(response)
end

get %r{/api/v1/matches/(?<match_id>\d+)/?$} do
  match_repo = MatchRepository.new()
  match = match_repo.get(params[:match_id].to_i)
  match.calculate_victories()
  response = match2api(match)

  JSON.generate(response)
end

get '/api/get_open_matches' do
  season_repo = SeasonRepository.new()
  match_repo = MatchRepository.new()
  player_repo = PlayerRepository.new

  current_season = season_repo.get_most_recent_season()
  divisions = current_season.divisions

  players = player_repo.get_all_players_by_id()

  response = []
  divisions.each do |d|
    division_data = {}
    division_data[:division_id] = d.id
    division_data[:name] = d.name
    division_data[:matches] = []
    open_matches = d.get_open_matches()
    open_matches.each do |m|
      name1 = players[m.players[0]].name
      name2 = players[m.players[1]].name
      name3 = players[m.players[2]].name
      name4 = players[m.players[3]].name
      match_data = {
        :id => m.id,
        :round => m.round,
        :player_ids => m.players,
        :players => [name1, name2, name3, name4],
        :submatches => [
          [[name1, name2], [name3, name4]],
          [[name1, name3], [name2, name4]],
          [[name1, name4], [name2, name3]],
        ]
      }
      division_data[:matches] << match_data
    end
    response << division_data
  end

  JSON.generate(response)
end

post '/api/set_result' do
  body = request.body.read
  data = JSON.parse(body)

  fd = open("results/result_" + Time.now.to_i.to_s + '_' + data['id'].to_s + ".json", "w")
  fd.write(body)
  fd.close()

  result = ResultProcessor.parse_result(data)
  if result == false
    JSON.generate({'result' => 'Match result already processed'})
  else
    JSON.generate({'result' => 'Match result correctly processed'})
  end
end

def match2api(m)
  response = {
    'id' => m.id,
    'division_id' => m.division_id,
    'round' => m.round,
    'players' => m.players
  }
  if m.played
    response['played'] = true
    response['scores'] = m.scores
    response['victories'] = m.victories
    response['time'] = m.time
    response['duration'] = m.duration
  else
    response['played'] = false
  end
  return response
end

def season2api(s)
  response = {
    'id' => s.id,
    'title' => s.title,
    'start' => s.start_time,
    'end' => s.end_time,
    'divisions' => [],
  }

  s.divisions.each do |d|
    response['divisions'] << division2api(d)
  end

  return response
end

def division2api(d)
  response = {
    'id' => d.id,
    'title' => d.name,
    'total_rounds' => d.total_rounds,
    'current_round' => d.current_round,
  }
  return response
end

def player2api(p)
  response = { 'name' => p.name }
  return response
end
