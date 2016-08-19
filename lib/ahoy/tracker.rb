module Ahoy
  class Tracker
    attr_reader :request, :controller

    def initialize(options = {})
      @store = Ahoy::Store.new(options.merge(ahoy: self))
      @controller = options[:controller]
      @request = options[:request] || @controller.try(:request)
      @options = options
    end

    def track(name, properties = {}, options = {})
      Safely.safely do
        if exclude?
          debug "Event excluded"
        else
          options = options.dup

          time = trusted_time(options[:time])
          event_token = ensure_uuid(options[:id] || generate_id)

          info = {
            event_token: event_token,
            visit_token: visit_token,
            name: name,
            properties: properties,
            time: time
          }

          @store.track_event(info)
        end
        true
      end
    end

    def track_visit(options = {})
      Safely.safely do
        if exclude?
          debug "Visit excluded"
        else
          if options[:defer]
            set_cookie("ahoy_track", true, nil, false)
          else
            options = options.dup

            options[:started_at] ||= Time.zone.now

            info = {
              visit_token: visit_token,
              visitor_token: visitor_token,
              time: options[:started_at]
            }

            keys = visit_properties.keys
            keys.each do |key|
              info[key] = visit_properties[key]
            end

            @store.track_visit(info)

            # ip = info[:ip]
            # info = {
            #   visit_token: visit_token
            # }
            # # Ahoy::GeocodeJob.perform_later(info)

            # deckhand = Deckhands::LocationDeckhand.new(ip)
            # Ahoy::VisitProperties::LOCATION_KEYS.each do |key|
            #   info[key] = deckhand.send(key)
            # end

            # @store.geocode(info)
          end
        end
        true
      end
    end

    def authenticate(user)
      Safely.safely do
        if exclude?
          debug "Authentication excluded"
        else
          info = {
            visit_token: visit_token,
            user: user
          }
          @store.authenticate(info)
        end
        true
      end
    end

    def visit
      @visit ||= @store.visit
    end

    def visit_id
      @visit_id ||= ensure_uuid(existing_visit_id || visit_token_helper)
    end

    def visitor_id
      @visitor_id ||= ensure_uuid(existing_visitor_id || visitor_token_helper)
    end

    def new_visit?
      !existing_visit_id
    end

    def set_visit_cookie
      set_cookie("ahoy_visit", visit_id, Ahoy.visit_duration)
    end

    def set_visitor_cookie
      unless existing_visitor_id
        set_cookie("ahoy_visitor", visitor_id, Ahoy.visitor_duration)
      end
    end

    def user
      @user ||= @store.user
    end

    # TODO better name
    def visit_properties
      @visit_properties ||= Ahoy::VisitProperties.new(request, @options.slice(:api))
    end

    def visit_token
      @visit_token ||= ensure_token(visit_token_helper)
    end

    def visitor_token
      @visitor_token ||= ensure_token(visitor_token_helper)
    end

    protected

    def visit_token_helper
      @visit_token_helper ||= existing_visit_id || (@options[:api] && request.params["visit_token"]) || generate_id
    end

    def visitor_token_helper
      @visitor_token_helper ||= existing_visitor_id || (@options[:api] && request.params["visitor_token"]) || generate_id
    end

    def set_cookie(name, value, duration = nil, use_domain = true)
      cookie = {
        value: value
      }
      cookie[:expires] = duration.from_now if duration
      domain = Ahoy.cookie_domain
      cookie[:domain] = domain if domain && use_domain
      request.cookie_jar[name] = cookie
    end

    def trusted_time(time)
      if !time || (@options[:api] && !(1.minute.ago..Time.now).cover?(time))
        Time.zone.now
      else
        time
      end
    end

    def exclude?
      @store.exclude?
    end

    # odd pattern for backwards compatibility
    # TODO remove this method in next major release
    def report_exception(e)
      Safely.safely do
        @store.report_exception(e)
        if Rails.env.development? || Rails.env.test?
          raise e
        end
      end
    end

    def generate_id
      @store.generate_id
    end

    def existing_visit_id
      @existing_visit_id ||= request && (request.headers["Ahoy-Visit"] || request.cookies["ahoy_visit"])
    end

    def existing_visitor_id
      @existing_visitor_id ||= request && (request.headers["Ahoy-Visitor"] || request.cookies["ahoy_visitor"])
    end

    def ensure_uuid(id)
      Ahoy.ensure_uuid(id)
    end

    def ensure_token(token)
      token.to_s.gsub(/[^a-z0-9\-]/i, "").first(64)
    end

    def debug(message)
      Rails.logger.debug { "[ahoy] #{message}" }
    end
  end
end
