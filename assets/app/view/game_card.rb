# frozen_string_literal: true

require 'lib/settings'
require 'lib/truncate'
require 'view/game_row'
require 'view/link'

module View
  class GameCard < Snabberb::Component
    include GameManager
    include Lib::Settings

    needs :user
    needs :gdata # can't conflict with game_data
    needs :confirm_delete, store: true, default: false
    needs :confirm_kick, store: true, default: nil
    needs :flash_opts, default: {}, store: true

    BUTTON_STYLE = {
      margin: '0',
      padding: '0.2rem 0',
      width: '3.5rem',
    }.freeze

    def render
      h('div.game.card', [
        render_header,
        render_body,
      ])
    rescue StandardError
      render_broken
    end

    def new?
      @gdata['status'] == 'new'
    end

    def owner?
      user_owns_game?(@user, @gdata)
    end

    def player?
      user_in_game?(@user, @gdata)
    end

    def players
      @gdata['players']
    end

    def acting?(player)
      return false unless player
      return false unless (acting = @gdata['acting'])

      acting.include?(player['id'] || player['name'])
    end

    def lookup_min(game)
      min_p, _max_p = game::PLAYER_RANGE
      return min_p unless game.respond_to?(:min_players)

      optional_rules = @gdata.dig('settings', 'optional_rules') || []
      game.min_players(optional_rules, @gdata['max_players']) || min_p
    end

    def render_header
      buttons = []

      bg_color =
        case @gdata['status']
        when 'new'
          buttons << render_invite_link if player? || owner?
          if user_in_game?(@user, @gdata)
            buttons << render_button('Leave', -> { leave_game(@gdata) })
          elsif players.size < @gdata['max_players']
            buttons << render_button('Join', -> { join_game(@gdata) })
          end
          JOIN_YELLOW
        when 'active'
          buttons << render_link(url(@gdata), -> { enter_game(@gdata) }, 'Enter')
          acting?(@user) ? color_for(:your_turn) : ENTER_GREEN
        when 'finished'
          buttons << render_link(url(@gdata), -> { enter_game(@gdata) }, 'Review')
          FINISHED_GREY
        when 'archived'
          buttons << h('p.bold', { style: { color: 'black' } }, 'Archived')
          FINISHED_GREY
        end

      if owner? && (@gdata['status'] == 'new' || @gdata['mode'] == :hotseat)
        buttons << if @confirm_delete != @gdata['id']
                     render_button('Delete', -> { store(:confirm_delete, @gdata['id']) })
                   else
                     render_button('Confirm', -> { delete_game(@gdata) })
                   end
      end

      game = Engine.meta_by_title(@gdata['title'])
      @min_p = lookup_min(game)

      can_start = owner? && new? && players.size >= @min_p
      buttons << render_button('Start', -> { start_game(@gdata) }) if can_start

      div_props = {
        style: {
          display: 'grid',
          grid: '1fr / minmax(10rem, 1fr) auto',
          gap: '0.5rem',
          justifyContent: 'space-between',
          padding: '0.3rem 0.5rem',
          backgroundColor: bg_color,
        },
      }

      buttons_props = {
        style: {
          display: 'grid',
          grid: '1fr / auto auto',
          gap: '0.3rem 0.4rem',
          direction: 'rtl',
          height: 'max-content',
        },
      }
      owner_props = { attrs: { title: @gdata['user']['name'].to_s } }

      text_props = {
        style: {
          color: contrast_on(bg_color),
        },
      }

      h('div.header', div_props, [
        h(:div, text_props, [
          h(:div, "Game: #{game.display_title}"),
          h('div.nowrap', owner_props, "Owner: #{@gdata['user']['name']}"),
        ]),
        h(:div, buttons_props, buttons),
      ])
    end

    def render_button(text, action)
      props = {
        style: {
          **BUTTON_STYLE,
        },
        on: {
          click: action,
        },
      }

      h(:button, props, text)
    end

    def render_link(href, click, text)
      h(
        Link,
        href: href,
        click: click,
        children: text,
        style: {
          **BUTTON_STYLE,
        },
        class: '.button_link'
      )
    end

    def render_time_or_date(ts_key)
      ts = Time.at(@gdata[ts_key]&.to_i || 0)
      time_or_date = ts > Time.now - 82_800 ? ts.strftime('%T') : ts.strftime('%F')
      h(:span, { attrs: { title: ts.strftime('%F %T') } }, time_or_date)
    end

    def render_optional_rules
      selected_rules = @gdata.dig('settings', 'optional_rules') || []
      return if selected_rules.empty?

      rendered_rules = Engine.meta_by_title(@gdata['title'])::OPTIONAL_RULES
        .select { |r| selected_rules.include?(r[:sym]) }
        .map { |r| r[:short_name] }
        .sort
        .join('; ')

      h(:div, [h(:strong, 'Optional Rules: '), rendered_rules])
    end

    def render_invite_link
      msg = 'Copied invite link to clipboard; you can share this link with '\
            'other players to invite them to the game'

      invite_url = url(@gdata)
      flash = lambda do
        `navigator.clipboard.writeText((window.location + invite_url).replace('//game', '/game'))`
        store(:flash_opts, { message: msg, color: 'lightgreen' }, skip: false)
      end
      render_link(invite_url, flash, 'Invite')
    end

    def render_body
      props = {
        style: {
          padding: '0.3rem 0.5rem',
        },
      }

      p_elm = players.map.with_index do |player, index|
        short_name = player['name'].truncate
        if owner? && new? && player['id'] != @user['id']
          button_props = {
            on: { click: -> { store(:confirm_kick, [@gdata['id'], player['id']]) } },
            attrs: { title: "Kick #{player['name']}!" },
            style: {
              padding: '0.1rem 0.3rem',
              margin: '0 0.3rem 0.1rem 0.3rem',
            },
          }

          elm = if @confirm_kick != [@gdata['id'], player['id']]
                  h(:button, button_props, "#{short_name} ❌")
                else
                  button_props['on'] = { click: -> { kick(@gdata, player) } }
                  h(:button, button_props, 'Kick! ❌')
                end

        else
          player_props = { attrs: { title: player['name'].to_s } }

          elm = h(:span, [
            h(acting?(player) ? :em : :span, player_props, short_name),
            index == (players.size - 1) || (owner? && new?) ? '' : ', ',
          ])
        end
        elm
      end

      children = [h(:div, [h(:strong, 'Id: '), @gdata['id'].to_s])]
      if @gdata['status'] == 'new'
        children << h(:div, [h(:i, 'Invite only game')]) if @gdata.dig('settings', 'unlisted')
        children << h(:div, [h(:i, 'Auto Routing')]) if @gdata.dig('settings', 'auto_routing')
      end
      children << h(:div, [h(:strong, 'Description: '), @gdata['description']]) unless @gdata['description'].empty?

      optional = render_optional_rules
      children << optional if optional
      children << h(:div, [h(:strong, 'Players: '), *p_elm]) unless %w[finished archived].include?(@gdata['status'])

      if new?
        seats = @min_p.to_s + (@min_p == @gdata['max_players'] ? '' : " - #{@gdata['max_players']}")
        children << h('div.inline', [h(:strong, 'Seats: '), seats])
        children << h('div.inline', { style: { float: 'right' } }, [
          h(:strong, 'Created: '),
          render_time_or_date('created_at'),
        ])
      elsif %w[finished archived].include?(@gdata['status'])
        result = @gdata['result']
          .sort_by { |_, v| -v }
          .map { |k, v| "#{k.truncate} #{v}" }
          .join(', ')

        children << h('div.inline', [
          h(:strong, 'Result: '),
          result,
        ])
        children << h('div.inline', { style: { float: 'right', paddingLeft: '1rem' } }, [
          h(:strong, 'Ended: '),
          render_time_or_date('updated_at'),
        ])
      elsif @gdata['round']
        children << h('div.inline', [
          h(:strong, 'Round: '),
          "#{@gdata['round']&.split(' ')&.first} #{@gdata['turn']}",
        ])

        children << h('div.inline', { style: { float: 'right' } }, [
          h(:strong, 'Updated: '),
          render_time_or_date('updated_at'),
        ])
      end

      h(:div, props, children)
    end

    def render_broken
      button = h(:div, [if @gdata['mode'] == 'hotseat'
                          if @confirm_delete != @gdata['id']
                            render_button('Delete', -> { store(:confirm_delete, @gdata['id']) })
                          else
                            render_button('Confirm', -> { delete_game(@gdata) })
                          end
                        end])

      header_props = {
        style: {
          display: 'grid',
          grid: '1fr / 1fr auto',
          padding: '0.3em 0.5rem',
          backgroundColor: 'salmon',
          color: 'black',
        },
      }

      body_props = {
        style: {
          padding: '0.3rem 0.5rem',
        },
      }

      h('div.game.card', [
        h('div.header', header_props, [
          h(:div, [
            h(:div, "Game: #{Engine.closest_display_title(@gdata['title'])}"),
            h('div.nowrap', 'Owner: You'),
          ]),
          button,
        ]),
        h(:div, body_props, [
          h('div.bold', 'Error rendering game card'),
          h(:div, [h('span.bold', 'Id: '), h(:span, @gdata['id'])]),
          h(:div, [h('span.bold', 'Data: '), h(:span, [@gdata.to_s[0..300], ' […]'])]),
        ]),
      ])
    end
  end
end
