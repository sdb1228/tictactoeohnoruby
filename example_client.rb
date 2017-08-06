#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'optparse'
require 'byebug'

def create_game(client)
  req = Net::HTTP::Post.new('/games', 'Content-Type' => 'application/json')
  res = client.request(req)

  JSON.parse(res.body)['id']
end

def join_game(client, player_name, game_id, auto)
  req = Net::HTTP::Post.new("/games/#{game_id}/players",
                            'Content-Type' => 'application/json')
  body = { name: player_name }
  if auto
    body[:pair] = 1
  end
  req.body = body.to_json

  JSON.parse(client.request(req).body)
end

def play(client, game_id, secret, board, cell)
  req = Net::HTTP::Post.new("/games/#{game_id}/moves",
                            'Content-Type' => 'application/json',
                            'X-Token' => secret)
  req.body = { board: board, cell: cell }.to_json

  JSON.parse(client.request(req).body)
end

def print_board(game)
  printed_boards = game['boards'].map do |board|
    board['rows'].map do |row|
      row.map { |cell| cell || '-' }.join(' ')
    end
  end

  [0, 3, 6].each do |i|
    (0..2).each do |j|
      puts [printed_boards[i][j],
            printed_boards[i + 1][j],
            printed_boards[i + 2][j]].join('  ')
    end
    puts "\n"
  end
end

def calculate_legal_move(board)
  board['rows'].flatten.each_with_index do |cell, index|
    return index if cell.nil?
  end
end

def calculate_horizontal_win(board, token)
  # Horizontal Win first row
  if board['rows'][0][0] == token && board['rows'][0][1] == token
    return 2 if board['rows'][0][2].nil?
  end

  if board['rows'][0][1] == token && board['rows'][0][2] == token
    return 0 if board['rows'][0][0].nil?
  end

  if board['rows'][0][0] == token && board['rows'][0][2] == token
    return 1 if board['rows'][0][1].nil?
  end

  # Horizontal Win second row
  if board['rows'][1][0] == token && board['rows'][1][1] == token
    return 5 if board['rows'][1][2].nil?
  end

  if board['rows'][1][1] == token && board['rows'][1][2] == token
    return 3 if board['rows'][1][0].nil?
  end

  if board['rows'][1][0] == token && board['rows'][1][2] == token
    return 4 if board['rows'][1][1].nil?
  end

  # Horizontal Win third row
  if board['rows'][2][0] == token && board['rows'][2][1] == token
    return 8 if board['rows'][2][2].nil?
  end

  if board['rows'][2][1] == token && board['rows'][2][2] == token
    return 6 if board['rows'][2][0].nil?
  end

  if board['rows'][2][0] == token && board['rows'][2][2] == token
    return 7 if board['rows'][2][1].nil?
  end
end

def calculate_verticle_win(board, token)
  # Verticle Win first row
  if board['rows'][0][0] == token && board['rows'][2][0] == token
    return 3 if board['rows'][1][0].nil?
  end

  if board['rows'][0][0] == token && board['rows'][1][0] == token
    return 6 if board['rows'][2][0].nil?
  end

  if board['rows'][1][0] == token && board['rows'][2][0] == token
    return 0 if board['rows'][0][0].nil?
  end

  # Verticle Win second row
  if board['rows'][0][1] == token && board['rows'][2][1] == token
    return 4 if board['rows'][1][1].nil?
  end

  if board['rows'][0][1] == token && board['rows'][1][1] == token
    return 7 if board['rows'][2][1].nil?
  end

  if board['rows'][1][1] == token && board['rows'][2][1] == token
    return 1 if board['rows'][0][1].nil?
  end

  # Verticle Win third row
  if board['rows'][0][2] == token && board['rows'][2][2] == token
    return 5 if board['rows'][1][2].nil?
  end

  if board['rows'][0][2] == token && board['rows'][1][2] == token
    return 8 if board['rows'][2][2].nil?
  end

  if board['rows'][1][2] == token && board['rows'][2][2] == token
    return 2 if board['rows'][0][2].nil?
  end
end

def calculate_diagonal_win(board, token)
  # Backslash Win
  if board['rows'][0][0] == token && board['rows'][2][2] == token
    return 5 if board['rows'][1][1].nil?
  end

  if board['rows'][1][1] == token && board['rows'][2][2] == token
    return 0 if board['rows'][0][0].nil?
  end

  if board['rows'][0][0] == token && board['rows'][1][1] == token
    return 8 if board['rows'][2][2].nil?
  end

  # Forwardslash Win
  if board['rows'][0][2] == token && board['rows'][2][0] == token
    return 5 if board['rows'][1][1].nil?
  end

  if board['rows'][0][2] == token && board['rows'][1][1] == token
    return 7 if board['rows'][2][0].nil?
  end

  if board['rows'][1][1] == token && board['rows'][2][0] == token
    return 2 if board['rows'][0][2].nil?
  end
end

def find_board(game)
  return game['nextBoard'] if game['nextBoard']

  game['boards'].each_with_index do |board, index|
    return index if board['playable']
  end
end

def calculate_move(board, token)
  no_moves = true
  board['rows'].each do |row|
    row.each do |cell|
      no_moves = false unless cell.nil?
    end
  end

  return 0 if no_moves

  cell = calculate_horizontal_win(board, token)
  return cell unless cell.nil?
  cell = calculate_verticle_win(board, token)
  return cell unless cell.nil?
  cell = calculate_diagonal_win(board, token)
  return cell unless cell.nil?
end

def calculate_blocking_move(board, token)
  cell = calculate_horizontal_win(board, token)
  return cell unless cell.nil?
  cell = calculate_verticle_win(board, token)
  return cell unless cell.nil?
  cell = calculate_diagonal_win(board, token)
  return cell unless cell.nil?
end

http_client = Net::HTTP.new('tictactoe.inseng.net', 80)
options = {}

OptionParser.new do |opts|
  opts.on('-p', '--player=PLAYER', 'Player name') do |v|
    options[:player_name] = v
  end

  opts.on('-g', '--game=GAME', 'Game id') do |v|
    options[:game] = v
  end

  opts.on('-a', '--auto', 'if set, pair with a robot player') do |v|
    options[:auto] = v
  end
end.parse!

player_name = options[:player_name]
game_id     = options[:game] ? options[:game] : create_game(http_client)

game = join_game(http_client, player_name, game_id, options[:auto])
loop do
  print_board(game)
  break if game['state'] != 'inProgress'

  token = game['players'].select do |player|
    player['name'] == 'sburnett'
  end.first['token']

  opponent_token = game['players'].reject do |player|
    player['name'] == 'sburnett'
  end.first['token']

  board = find_board(game)
  cell = calculate_move(game['boards'][board], token)
  if cell.nil?
    cell = calculate_blocking_move(game['boards'][board], opponent_token)
  end

  cell = calculate_legal_move(game['boards'][board]) if cell.nil?

  puts "MY MOVE BOARD #{board} CELL #{cell}"

  game = play(
    http_client,
    game['id'],
    game['currentPlayer']['secret'],
    board,
    cell
  )
end

puts "Game state: #{game['state']}"
puts "Game winner: #{game['winner'] ? game['winner']['name'] : 'None'}"
