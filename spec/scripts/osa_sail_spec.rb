# frozen_string_literal: true

require_relative '../spec_helper'

# osa-sail is a column-0 module of definitions with one guarded entry call, so the spec
# loads the real file and drives OsaSail::Trip through a fake Game. The fake answers each
# command with a line recorded on a sloop at Solhaven (Nisugi's October 2026 GST sessions),
# and sails the ship one room per idle tick along whatever heading the wheel was turned to.
OSA_SAIL_NO_AUTORUN = true unless defined?(OSA_SAIL_NO_AUTORUN)
load find_lic_source('osa-sail.lic', from: __dir__)

RSpec.describe OsaSail do
  SOLHAVEN = 7116362
  KRAKENS_FALL = 7116096

  describe 'the ocean data' do
    it 'carries the full chart' do
      expect(OsaSail::Data::OCEAN.size).to eq(2200)
      expect(OsaSail::Data::PORTS.size).to eq(12)
      expect(OsaSail::Data::PIERS.size).to eq(274)
    end

    it 'places every port on the chart and every pier in a port' do
      OsaSail::Data::PORTS.each_value { |p| expect(OsaSail::Data::OCEAN).to have_key(p[:uid]) }
      OsaSail::Data::PIERS.each_value { |port, _| expect(OsaSail::Data::PORTS).to have_key(port) }
    end

    it 'has fewer than 50 links that do not run true' do
      not_true = OsaSail::Data::OCEAN.keys.sum do |uid|
        OsaSail::Data::HEADINGS.count { |h| OsaSail::Data.toward(uid, h) && !OsaSail::Data.runs_true?(uid, h) }
      end
      expect(not_true).to be < 50
    end

    it 'finds ports by exact name, prefix and word prefix' do
      expect(OsaSail::Data.port_named('Solhaven')).to eq('Solhaven')
      expect(OsaSail::Data.port_named('kraken')).to eq("Kraken's Fall")
      expect(OsaSail::Data.port_named('landing')).to eq("Wehnimer's Landing")
      expect(OsaSail::Data.port_named('grief')).to eq("Sailor's Grief")
      expect(OsaSail::Data.port_named('atlantis')).to be_nil
    end

    it 'maps a pier title back to its rooms and port' do
      rooms = OsaSail::Data.piers_titled("North 'Haven Quay, Green Pier")
      expect(rooms).not_to be_empty
      expect(OsaSail::Data.port_of_pier(rooms.first)).to eq('Solhaven')
      expect(OsaSail::Data.port_looking('diverse')).to eq('Solhaven')
    end
  end

  describe OsaSail::Course do
    it 'reaches every port from every other port' do
      OsaSail::Data::PORTS.keys.permutation(2) do |a, b|
        expect(OsaSail::Course.plot(OsaSail::Data::PORTS[a][:uid], OsaSail::Data::PORTS[b][:uid])).not_to be_nil, "#{a} -> #{b}"
      end
    end

    it 'sails Solhaven to Kraken\'s Fall in at most 28 rooms and 6 turns' do
      legs = OsaSail::Course.plot(SOLHAVEN, KRAKENS_FALL)
      expect(OsaSail::Course.rooms(legs)).to be <= 28
      expect(OsaSail::Course.turns(legs)).to be <= 6
      expect(legs.first[1].first).to eq(OsaSail::Data.toward(SOLHAVEN, legs.first[0]))
    end

    it 'charges no turn for a heading already held' do
      legs = OsaSail::Course.plot(SOLHAVEN, KRAKENS_FALL)
      held = legs.first[0]
      again = OsaSail::Course.plot(SOLHAVEN, KRAKENS_FALL, holding: held)
      expect(again.first[0]).to eq(held)
      expect(OsaSail::Course.turns(again, holding: held)).to eq(again.size - 1)
    end

    it 'returns an empty course when already there' do
      expect(OsaSail::Course.plot(SOLHAVEN, SOLHAVEN)).to eq([])
    end
  end

  describe OsaSail::Deck do
    it 'reads the hull and deck from a title' do
      expect(OsaSail::Deck.parse_title("[Sloop, Main Deck] (-7117010)")).to eq(['Sloop', 'Main Deck'])
      expect(OsaSail::Deck.parse_title("[Man O' War, Forward Crow's Nest]")).to eq(["Man O' War", "Forward Crow's Nest"])
      expect(OsaSail::Deck.parse_title('[Enemy Ship, Helm]')).to be_nil
      expect(OsaSail::Deck.parse_title("[North 'Haven Quay, Green Pier]")).to be_nil
    end

    it 'names hulls loosely' do
      expect(OsaSail::Deck.hull_by_name("man o' war")).to eq("Man O' War")
      expect(OsaSail::Deck.hull_by_name('MAN O WAR')).to eq("Man O' War")
      expect(OsaSail::Deck.hull_by_name('brig')).to eq('Brigantine')
    end

    it 'walks the sloop' do
      expect(OsaSail::Deck.route('Sloop', 'Main Deck', 'Helm')).to eq([['west', 'Helm']])
      expect(OsaSail::Deck.route('Sloop', "Captain's Quarters", "Crow's Nest")).to eq([['out', 'Helm'], ['east', 'Main Deck'], ['up', "Crow's Nest"]])
      expect(OsaSail::Deck.route('Sloop', 'Main Deck', 'Forward Deck')).to be_nil
    end

    it 'walks the larger hulls' do
      expect(OsaSail::Deck.route('Carrack', 'Bow', 'Main Deck').map(&:first)).to eq(%w[west west])
      expect(OsaSail::Deck.route('Brigantine', 'Forward Deck', 'Bow')).to be_nil
      expect(OsaSail::Deck.route('Galleon', 'Social Room', 'Main Deck').map(&:first)).to eq(%w[west west up])
    end

    it "puts the Man O' War's Mid Deck between Main and Forward" do
      expect(OsaSail::Deck.route("Man O' War", 'Main Deck', 'Forward Deck').map(&:last)).to eq(['Mid Deck', 'Forward Deck'])
      expect(OsaSail::Deck.route("Man O' War", 'Cargo Hold', "Forward Crow's Nest").map(&:first)).to eq(%w[up east east up])
      expect(OsaSail::Deck.route("Man O' War", 'Bow', 'Main Deck').map(&:first)).to eq(%w[west west west])
    end

    it 'lists every mast deck as a deck the hull has' do
      OsaSail::Data::HULLS.each do |hull, h|
        h[:masts].each { |m| expect(h[:decks]).to include(m), "#{hull} mast #{m}" }
      end
    end
  end

  describe OsaSail::Lines do
    it 'reads the dock handler' do
      quote = %(A dock handler says, "You're about to launch your sloop.  It'll cost about 5,000 silvers to get it ready.  I'll take silvers or a note.  Are you ready for adventure?")
      expect(OsaSail::Lines::FEE.match(quote)[1]).to eq('5,000')
      pier = %(Kilvath barks a few orders and says, "Looks like we have some space around the North 'Haven Quay, Green Pier."  The dock handler points)
      expect(OsaSail::Lines::PIER_NAMED.match(pier)[1]).to eq("North 'Haven Quay, Green Pier")
      expect(OsaSail::Lines::ALREADY_DOCKED.match(%(A dock handler says, "What?  You already have a ship docked at the Kraken's Fall, Fourth Pier!"))[1]).to eq("Kraken's Fall, Fourth Pier")
    end

    it 'reads the plank' do
      expect(OsaSail::Lines::PLANK_DEPLOYS).to match('A shadowy black mistwood gangplank suddenly protrudes from the side of the sloop before slamming down.')
      expect(OsaSail::Lines::PLANK_DEPLOYS).to match('As you approach the mistwood gangplank you suddenly realize you already deployed it!')
      expect(OsaSail::Lines::BOARDED).to match('You make your way up the mistwood gangplank and aboard the mistwood sloop.')
      expect(OsaSail::Lines::BOARDED).to match('You make your way across the mistwood gangplank.')
    end

    it 'reads the sails and the anchor' do
      half = 'Holding the line in both hands you slowly lower the canvas sail until it is at half mast.'
      full = 'Holding the line in both hands you slowly lower the canvas sail until it is fully open.'
      expect(OsaSail::Lines::SAIL_STATE).to match(half)
      expect(OsaSail::Lines::SAIL_FULL).not_to match(half)
      expect(OsaSail::Lines::SAIL_FULL).to match(full)
      expect(OsaSail::Lines::SAIL_FULL).to match('The canvas sail is already lowered as far as it can go!')
      expect(OsaSail::Lines::ANCHOR_UP).to match('give it one final push.  The wooden capstan clicks audibly into a locking position as the anchor settles against the hull.')
      expect(OsaSail::Lines::ANCHOR_DOWN).to match('The chain is unfurled and the anchor is deployed.  You could try PUSHing to raise it.')
    end

    it 'reads the voyage' do
      expect(OsaSail::Lines::MOVED.match('The mistwood sloop cuts through the ocean, heading north at full speed.')[2]).to eq('north')
      expect(OsaSail::Lines::MOVED.match('The mistwood sloop drifts slowly southwest, its sails fully raised.')[1]).to eq('southwest')
      expect(OsaSail::Lines::STEERED).to match('You grab hold of the wooden wheel and do your best to steer the ship to the north.')
      expect(OsaSail::Lines::STEERED).to match('The wooden wheel is already turned that way!')
      arrival = "The mistwood sloop drifts steadily toward the diverse port.  Shouts are heard from the piers nearby directing the sloop to North 'Haven Quay, Green Pier.  As the mistwood sloop sails toward the designated pier, a pair of workers swing aboard from a nearby platform."
      m = OsaSail::Lines::ARRIVED.match(arrival)
      expect(m[1]).to eq('diverse')
      expect(m[2]).to eq("North 'Haven Quay, Green Pier")
    end

    it 'reads the three recorded events at sea' do
      expect(OsaSail::Lines::SWELL).to match('A large swell crashes into the side of the mistwood sloop!  The sound of the anchor can be heard rattling down the side of the mistwood sloop.')
      expect(OsaSail::Lines::WHEEL_SPUN).to match('The mistwood sloop suddenly drifts from its course as the wooden wheel spins out of control!')
      expect(OsaSail::Lines::RIGGING_LOOSE).to match('The sound of ropes coming free of the rigging prelude the whipping of a storm grey canvas sail!')
    end
  end

  describe OsaSail::Watcher do
    let(:watcher) { described_class.new }

    it 'turns recorded lines into events and strips markup' do
      expect(watcher.see('<pushBold/>The <a exist="1" noun="sloop">mistwood sloop</a> cuts through the ocean, heading north at full speed.<popBold/>')).to eq([:moved, 'n'])
      expect(watcher.see('A large swell crashes into the side of the mistwood sloop!  The sound of the anchor can be heard rattling down the side of the mistwood sloop.')).to eq([:anchor_down])
      expect(watcher.see('The mistwood sloop suddenly drifts from its course as the wooden wheel spins out of control!')).to eq([:heading_lost])
      expect(watcher.see('The sound of ropes coming free of the rigging prelude the whipping of a storm grey canvas sail!')).to eq([:sails_furled])
      expect(watcher.see("The mistwood sloop drifts steadily toward the bustling port.  Shouts are heard from the piers nearby directing the sloop to Kraken's Fall, Fourth Pier.  As the sloop")).to eq([:arrived, 'bustling', "Kraken's Fall, Fourth Pier"])
      expect(watcher.see('You grab hold of the wooden wheel and do your best to steer the ship to the north.')).to be_nil
      expect(watcher.take_all.size).to eq(5)
    end

    it 'passes the server string through its hook unchanged' do
      line = '<pushBold/>The mistwood sloop cuts through the ocean, heading south at full speed.<popBold/>'
      expect(watcher.hook.call(line)).to equal(line)
    end
  end

  # A sloop, its pier and the sea between Solhaven and Kraken's Fall, answering with recorded
  # lines. The ship moves one room per idle tick along the heading the wheel holds, and docks
  # when the wheel is turned to port in a port room.
  class FakeGame
    attr_reader :commands, :walks, :logs, :position

    def initialize(start_title:, swell_after: nil, ashore: false)
      @title = start_title
      @commands = []
      @walks = []
      @logs = []
      @position = nil
      @held = nil
      @moves = 0
      @swell_after = swell_after
      @ashore = ashore
      @pushes = 0
      @sail_pulls = 0
      @departs = 0
      @asks = 0
      @at_pier = false
    end

    def title = @title
    def log(msg) = @logs << msg
    def spell_known?(_) = false
    def cast(_, _) = nil
    def watch(watcher) = @watcher = watcher
    def unwatch = @watcher = nil
    def confirm?(_) = true
    def current_uid = nil

    def npcs
      @ashore && !@at_pier ? [Struct.new(:id, :noun, :name).new(482_307, 'handler', 'dock handler')] : []
    end

    def objects
      @at_pier ? [Struct.new(:noun, :name).new('sloop', 'shadowy black mistwood sloop')] : []
    end

    def quiet(command, _pattern, **)
      @commands << command
      ['Ships you own:', 'SLOOP    Docked at: Solhaven'] if command == 'ship info'
    end

    def walk_to(uid)
      @walks << uid
      @at_pier = OsaSail::Data::PIERS.key?(uid)
      true
    end

    def idle
      return unless @held
      if @held == 'port'
        if (port = OsaSail::Data.port_of_ocean_room(@position))
          @watcher.see("The mistwood sloop drifts steadily toward the #{OsaSail::Data::PORTS[port][:looks]} port.  Shouts are heard from the piers nearby directing the sloop to #{port}, Fourth Pier.  As the mistwood sloop sails toward the designated pier, a pair of workers swing aboard.")
          @held = nil
        end
        return
      end
      nxt = OsaSail::Data.toward(@position, @held)
      raise "fake ship sailed #{@held} off the chart from #{@position}" unless nxt
      @position = nxt
      @moves += 1
      @watcher.see("The mistwood sloop cuts through the ocean, heading #{OsaSail::Data::HEADING_WORD[@held]} at full speed.")
      if @swell_after && @moves == @swell_after
        @watcher.see('A large swell crashes into the side of the mistwood sloop!  The sound of the anchor can be heard rattling down the side of the mistwood sloop.')
        @held = nil
        @anchor_down = true
      end
    end

    def send(command, _expect, **)
      @commands << command
      case command
      when /^ask #\d+ about retrieve sloop$/
        @asks += 1
        if @asks == 1
          %(A dock handler says, "You're about to launch your sloop.  It'll cost about 5,000 silvers to get it ready.  I'll take silvers or a note.  Are you ready for adventure?")
        else
          %(Kilvath says, "Looks like we have some space around the North 'Haven Quay, Green Pier."  The dock handler points to the northwest.)
        end
      when 'go sloop'
        @title = '[Sloop, Main Deck] (-7117010)'
        'A shadowy black mistwood gangplank suddenly protrudes from the side of the sloop before slamming down.'
      when 'watch ocean' then 'You begin to watch the ocean waters surrounding the ship....'
      when 'ship flag' then 'The mistwood sloop is currently flying no flag.'
      when 'ship flag white' then 'Ashryn just raised a white flag atop the mistwood sloop.'
      when 'pull gangplank' then 'You grab the mistwood gangplank in both hands and pull it back up on the deck.'
      when 'lower sail'
        @sail_pulls += 1
        @sail_pulls.odd? ? 'you slowly lower the canvas sail until it is at half mast.' : 'you slowly lower the canvas sail until it is fully open.'
      when 'push capstan'
        @pushes += 1
        if @pushes % 3 == 0
          @anchor_down = false
          'Using all your might you give it one final push.  The wooden capstan clicks audibly into a locking position as the anchor settles against the hull.'
        else
          'Using all your might you shove the wooden capstan along for several rotations!'
        end
      when 'depart'
        @departs += 1
        if @departs.odd?
          'Are you sure you are ready to DEPART from your current location?  [Repeat this command within 30 seconds to confirm it.]'
        else
          @position = SOLHAVEN
          'The mistwood sloop starts to rock as it drifts out into the open sea...'
        end
      when /^turn wheel (\w+)$/
        word = Regexp.last_match(1)
        raise 'turned the wheel with the anchor down' if @anchor_down
        @held = word == 'port' ? 'port' : OsaSail::Data::WORD_HEADING.fetch(word)
        "You grab hold of the wooden wheel and do your best to steer the ship to the #{word}."
      when 'push gangplank' then 'You give the mistwood gangplank a good shove, deploying it below.'
      when 'go gangplank'
        @title = "[Kraken's Fall, Fourth Pier] (7118240)"
        'You make your way across the mistwood gangplank.'
      when 'west' then step('Helm')
      when 'east' then step('Main Deck')
      when 'up' then step("Crow's Nest")
      when 'down' then step(@title.include?("Crow's Nest") ? 'Main Deck' : 'Cargo Hold')
      when 'go door' then step("Captain's Quarters")
      when 'out' then step('Helm')
      else
        raise "fake game has no answer for #{command.inspect}"
      end
    end

    private

    def step(deck)
      @title = "[Sloop, #{deck}]"
      @title
    end
  end

  describe OsaSail::Trip do
    def wheel_turns(game)
      game.commands.grep(/^turn wheel/)
    end

    it 'sails a docked sloop from Solhaven to Kraken\'s Fall and steps ashore' do
      game = FakeGame.new(start_title: '[Sloop, Main Deck] (-7117010)')
      trip = described_class.new(game, "Kraken's Fall", confirm: false)
      expect(trip.run).to eq(:arrived)

      c = game.commands
      expect(c.index('ship flag white')).to be < c.index('pull gangplank')
      expect(c.index('pull gangplank')).to be < c.index('lower sail')
      expect(c.rindex('lower sail')).to be < c.index('push capstan')
      expect(c.rindex('push capstan')).to be < c.index('depart')
      expect(c.count('depart')).to eq(2)
      expect(c.last(2)).to eq(['push gangplank', 'go gangplank'])

      legs = OsaSail::Course.plot(SOLHAVEN, KRAKENS_FALL)
      expect(wheel_turns(game).size).to eq(legs.size + 1)
      expect(wheel_turns(game).last).to eq('turn wheel port')
      expect(game.position).to eq(KRAKENS_FALL)
      expect(trip.position).to eq(KRAKENS_FALL)
      expect(game.title).to start_with("[Kraken's Fall")
    end

    it 'raises the anchor again after a swell and still arrives' do
      game = FakeGame.new(start_title: '[Sloop, Main Deck] (-7117010)', swell_after: 4)
      trip = described_class.new(game, "Kraken's Fall", confirm: false)
      expect(trip.run).to eq(:arrived)

      c = game.commands
      first_depart = c.index('depart')
      expect(c[first_depart..].count('push capstan')).to be >= 3
      expect(game.logs).to include(a_string_matching(/swell dropped the anchor/))
      expect(game.position).to eq(KRAKENS_FALL)
    end

    it 'retrieves the ship from the dock handler when ashore' do
      game = FakeGame.new(start_title: "[North 'Haven Quay, Catwalk] (7124101)", ashore: true)
      trip = described_class.new(game, "Kraken's Fall", confirm: false)
      expect(trip.run).to eq(:arrived)

      expect(game.walks.first).to eq(OsaSail::Data::PORTS['Solhaven'][:handler])
      expect(game.walks[1..]).to include(*OsaSail::Data.piers_titled("North 'Haven Quay, Green Pier").first(1))
      expect(game.commands.count { |x| x.start_with?('ask #') }).to eq(2)
      expect(game.commands.index('go sloop')).to be < game.commands.index('ship flag')
    end

    it 'halts when the ship is already at the target port' do
      game = FakeGame.new(start_title: '[Sloop, Main Deck] (-7117010)')
      trip = described_class.new(game, 'Solhaven', confirm: false)
      expect { trip.run }.to raise_error(OsaSail::Halt, /already at Solhaven/)
    end

    it 'halts aboard an enemy ship' do
      game = FakeGame.new(start_title: '[Enemy Ship, Main Deck]')
      trip = described_class.new(game, "Kraken's Fall", confirm: false)
      expect { trip.run }.to raise_error(OsaSail::Halt, /enemy ship/)
    end
  end
end
