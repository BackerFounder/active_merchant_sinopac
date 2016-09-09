module OffsitePayments #:nodoc:
  module Integrations #:nodoc:
    module Sinopac
      mattr_accessor :account
      mattr_accessor :api_key_data1
      mattr_accessor :api_key_data2
      mattr_accessor :api_key_data3

      def self.api_host
        mode = OffsitePayments.mode
        case mode
        when :production
          "ecapi.sinopac.com"
        when :development, :test
          "sandbox.sinopac.com"
        else
          raise StandardError, "Integration mode set to an invalid value: #{mode}"
        end
      end

      def self.service_url
        "https://#{api_host}/SinoPacWebCard/Pages/PageRedirect.aspx"
      end

      def self.notification(post)
        Notification.new(post)
      end

      class Helper < OffsitePayments::Helper
        # Replace with the real mapping
        mapping :account, "ShopNO" # 會員編號，例如 AA0001，必填
        mapping :amount, "Amount" # 訂單總金額，需保留小數二位,例如 180 元則帶 18000,且金額必需 > 0，必填

        FIELD_NAMES = [
          "KeyNum", # 驗証組別，必填
          "OrderNO", # 用戶訂單編號,不可重複，必填
          "CurrencyID", # 固定為 NTD，必填
          "PrdtName", # 收款名稱，最長 60 個中英文字(不可有單引號、百分比)，必填
          "Memo", # 備註，最長 30 個中英文字(不可有單引號、百分比)
          "PayerName", # 付款人-姓名
          "PayerMobile", # 付款人-行動電話
          "PayerAddress", # 付款人-地址
          "PayerEmail", # 付款人-電子郵件
          "ReceiverName", # 收貨人-姓名
          "ReceiverMobile", # 收貨人-行動電話
          "ReceiverAddress", # 收貨人-地址
          "ReceiverEmail", # 收貨人-電子郵件
          "IsDividend", # 是否使用紅利折抵
          "IsStaging", # 是否使用分期付款
          "Staging", # 分期期數
          "AutoBilling", # 自動請款
          "Param1", # 自訂參數一
          "Param2", # 自訂參數二
          "Param3" # 自訂參數三
        ].freeze

        FIELD_NAMES.each do |field_name|
          mapping field_name.underscore.to_sym, field_name
        end

        def digest
          order_no = @fields["OrderNO"]
          key_num = @fields["KeyNum"]
          shop_no = @fields["ShopNO"]
          amount = @fields["Amount"]
          api_key_datum = {
            "1" => OffsitePayments::Integrations::Sinopac.api_key_data1,
            "2" => OffsitePayments::Integrations::Sinopac.api_key_data2,
            "3" => OffsitePayments::Integrations::Sinopac.api_key_data3
          }[key_num]

          raw_data = "POST:#{order_no}:#{shop_no}:#{amount}:#{api_key_datum}"
          hexdigest = Digest::SHA256.hexdigest raw_data
          add_field "Digest", hexdigest
        end
      end

      class Notification < OffsitePayments::Notification
        def complete?
          status.eql?("S")
        end

        def item_id
          params["OrderNO"]
        end

        def transaction_id
          params["TSNO"]
        end

        # When was this payment received by the client.
        def received_at
          params[""]
        end

        def payer_email
          params["PayerEmail"]
        end

        def receiver_email
          params["ReceiverEmail"]
        end

        def security_key
          params[""]
        end

        # the money amount we received in X.2 decimal.
        def gross
          params[""]
        end

        # Was this a test transaction?
        def test?
          params["param3"] == "test"
        end

        def status
          params["Status"]
        end

        # Acknowledge the transaction to Sinopac. This method has to be called after a new
        # apc arrives. Sinopac will verify that all the information we received are correct and will return a
        # ok or a fail.
        #
        # Example:
        #
        #   def ipn
        #     notify = SinopacNotification.new(request.raw_post)
        #
        #     if notify.acknowledge
        #       ... process order ... if notify.complete?
        #     else
        #       ... log possible hacking attempt ...
        #     end
        def acknowledge(authcode = nil)
          payload = raw

          uri = URI.parse(Sinopac.notification_confirmation_url)

          request = Net::HTTP::Post.new(uri.path)

          request["Content-Length"] = payload.size.to_s
          request["User-Agent"] = "Active Merchant -- http://activemerchant.org/"
          request["Content-Type"] = "application/x-www-form-urlencoded"

          http = Net::HTTP.new(uri.host, uri.port)
          http.verify_mode    = OpenSSL::SSL::VERIFY_NONE unless @ssl_strict
          http.use_ssl        = true

          response = http.request(request, payload)

          # Replace with the appropriate codes
          raise StandardError.new("Faulty Sinopac result: #{response.body}") unless ["AUTHORISED", "DECLINED"].include?(response.body)
          response.body == "AUTHORISED"
        end

        private

        # Take the posted data and move the relevant data into a hash
        def parse(post)
          @raw = post.to_s
          @raw.split("&").each do |line|
            key, value = *line.scan(%r{^([A-Za-z0-9_.-]+)\=(.*)$}).flatten
            params[key] = CGI.unescape(value.to_s) if key.present?
          end
        end
      end

      def self.setup
        yield(self)
      end
    end
  end
end
