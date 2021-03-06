require 'travis/backfill/task/base'

# The first `push` request payload that included the sender field was
# id=11004914 on 2014-09-24 06:26:35 UTC. Before that date GitHub did not
# include a sender, but a pusher, which did not include the GitHub id for the
# user, but only their login. We ignore this, as it's ambigious.
#
# Pull request payloads included the sender from the start. The first pull
# request was id=313589 on 2012-04-19 05:44:12.

module Travis
  module Backfill
    module Task
      module Sender
        class Update < Base
          register :task, 'sender:update'

          attr_reader :record

          def run?
            attrs[:github_id] && incomplete?
          end

          def run
            return unless @record = find_or_create
            update_request unless request.sender_id
            update_build   unless build.nil? || build.sender_id
          end
          # time :run
          meter :run

          private

            def incomplete?
              request.sender_id.nil? || build.try(:sender_id).nil?
            end

            def find_or_create
              record = find
              record ||= create unless api_or_cron?
              record
            rescue ActiveRecord::RecordNotUnique => e
              warn "User record not uniq for request=#{request.id}. Retrying."
              sleep 0.01
              retry
            end

            def find
              api_or_cron? ? find_by_id : find_by_github_id
            end
            # time :find

            def find_by_id
              ::User.where(id: sender.id.value).first if sender.id.value
            end

            def find_by_github_id
              ::User.where(github_id: attrs[:github_id]).first if attrs[:github_id]
            end

            def create
              ::User.create(attrs) if attrs[:github_id] && attrs[:login]
            end
            # time :create

            def update_request
              request.sender = record
              request.save!
            end
            # time :update_request

            def update_build
              build.sender = record
              build.save!
            end
            # time :update_build

            def attrs
              @attrs ||= {
                github_id:  sender.id.value,
                login:      sender.login.value,
                avatar_url: sender.avatar_url.value
              }
            end

            def sender
              api_or_cron? ? data.user : data.sender
            end

            def api_or_cron?
              ['api', 'cron'].include?(request.event_type)
            end

            def data
              params[:data]
            end

            def request
              params[:request]
            end

            def build
              params[:build]
            end
        end
      end
    end
  end
end
