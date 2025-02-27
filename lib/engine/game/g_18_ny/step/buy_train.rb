# frozen_string_literal: true

require_relative '../../../step/buy_train'
require_relative '../../../step/automatic_loan'

module Engine
  module Game
    module G18NY
      module Step
        class BuyTrain < Engine::Step::BuyTrain
          def actions(entity)
            actions = super
            return actions unless entity.corporation?
            return [] if entity.receivership?

            if must_buy_train?(entity)
              actions.delete('pass')
              actions << 'buy_train'
            end
            actions << 'scrap_train' unless scrappable_trains(entity).empty?
            actions << 'take_loan' if can_take_loan?(entity)
            actions << 'pass' if !actions.empty? && !must_buy_train?(entity)
            actions.uniq
          end

          def ebuy_president_can_contribute?(corporation)
            super && president_may_contribute?(corporation)
          end

          def president_may_contribute?(entity, _shell = nil)
            super && !@train_salvaged
          end

          def scrappable_trains(entity)
            entity.trains
          end

          def scrap_info(_train)
            ''
          end

          def scrap_button_text(_train)
            'Salvage'
          end

          def can_take_loan?(entity)
            !can_afford_train?(entity) && entity.trains.empty? && !@train_salvaged && @game.can_take_loan?(entity)
          end

          def can_afford_train?(entity)
            entity.cash >= @game.depot.min_depot_price
          end

          def ebuy_offer_only_cheapest_depot_train?
            @loan_taken
          end

          def needed_cash(_entity)
            @loan_taken ? @depot.min_depot_price : @depot.max_depot_price
          end

          def setup
            super
            @train_salvaged = false
            @loan_taken = false
          end

          def can_issue_shares?(entity)
            must_buy_train?(entity) && !@train_salvaged && entity.cash < @depot.max_depot_price
          end

          def issuable_shares(entity)
            # Issue is part of emergency buy
            return [] unless can_issue_shares?(entity)

            super
          end

          def selling_minimum_shares?(bundle)
            return true if bundle.owner&.corporation?

            super
          end

          def spend_minmax(entity, train)
            minmax = super
            minmax[0] = train.price if train.owner&.corporation? && !train.owner.loans.empty?
            minmax[-1] = train.price unless entity.loans.empty?
            minmax
          end

          def pass_if_cannot_buy_train?(entity)
            scrappable_trains(entity).empty?
          end

          def process_buy_train(action)
            train = action.train
            check_for_cheapest_train(train) if train.from_depot? && @loan_taken

            super
          end

          def process_take_loan(action)
            @game.take_loan(action.entity)
            @loan_taken = true
          end

          def process_scrap_train(action)
            raise GameError, 'Can only scrap trains owned by the corporation' if action.entity != action.train.owner

            @train_salvaged = true
            @game.salvage_train(action.train)
          end
        end
      end
    end
  end
end
