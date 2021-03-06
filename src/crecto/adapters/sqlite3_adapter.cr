module Crecto
  module Adapters
    #
    # Adapter module for SQLite3
    #
    module SQLite3
      @@ENV_KEY = "SQLITE3_PATH"
      extend BaseAdapter

      #
      # Query data store using *sql*, returning multiple rows
      #
      def self.run(operation : Symbol, sql : String, params : Array(DbValue))
        case operation
        when :sql
          execute(sql, params)
        end
      end

      def self.exec_execute(query_string, params, tx : DB::Transaction?)
        return exec_execute(query_string, params) if tx.nil?
        tx.connection.exec(query_string, params)
      end

      def self.exec_execute(query_string, tx : DB::Transaction?)
        return exec_execute(query_string) if tx.nil?
        tx.connection.exec(query_string)
      end

      def self.exec_execute(query_string, params : Array)
        start = Time.now
        results = get_db().exec(query_string, params)
        DbLogger.log(query_string, Time.new - start, params)
        results
      end

      def self.exec_execute(query_string)
        start = Time.now
        results = get_db().exec(query_string)
        DbLogger.log(query_string, Time.new - start)
        results
      end

      private def self.get(queryable, id)
        q = ["SELECT *"]
        q.push "FROM #{queryable.table_name}"
        q.push "WHERE #{queryable.primary_key_field}=?"
        q.push "LIMIT 1"

        execute(q.join(" "), [id])
      end

      private def self.insert(changeset, tx : DB::Transaction?)
        fields_values = instance_fields_and_values(changeset.instance)

        q = ["INSERT INTO"]
        q.push "#{changeset.instance.class.table_name}"
        q.push "(#{fields_values[:fields].join(", ")})"
        q.push "VALUES"
        q.push "(#{(1..fields_values[:values].size).map { "?" }.join(", ")})"

        res = exec_execute(q.join(" "), fields_values[:values], tx)
        execute("SELECT * FROM #{changeset.instance.class.table_name} WHERE #{changeset.instance.class.primary_key_field} = #{res.last_insert_id}")
      end

      private def self.update_begin(table_name, fields_values)
        q = ["UPDATE"]
        q.push "#{table_name}"
        q.push "SET"
        q.push fields_values[:fields].map { |field_value| "#{field_value}=?" }.join(", ")
        q
      end

      private def self.update(changeset, tx)
        fields_values = instance_fields_and_values(changeset.instance)

        q = update_begin(changeset.instance.class.table_name, fields_values)
        q.push "WHERE"
        q.push "#{changeset.instance.class.primary_key_field}=#{changeset.instance.pkey_value}"

        exec_execute(q.join(" "), fields_values[:values], tx)
        execute("SELECT * FROM #{changeset.instance.class.table_name} WHERE #{changeset.instance.class.primary_key_field} = #{changeset.instance.pkey_value}")
      end

      private def self.delete(changeset, tx : DB::Transaction?)
        q = delete_begin(changeset.instance.class.table_name)
        q.push "WHERE"
        q.push "#{changeset.instance.class.primary_key_field}=#{changeset.instance.pkey_value}"

        sel = execute("SELECT * FROM #{changeset.instance.class.table_name} WHERE #{changeset.instance.class.primary_key_field}=#{changeset.instance.pkey_value}") if !tx.nil?
        return exec_execute(q.join(" "), tx) if !tx.nil?
        sel
      end

      private def self.delete(queryable, query, tx : DB::Transaction?)
        params = [] of DbValue | Array(DbValue)

        q = delete_begin(queryable.table_name)
        q.push wheres(queryable, query, params) if query.wheres.any?
        q.push or_wheres(queryable, query, params) if query.or_wheres.any?

        exec_execute(q.join(" "), params, tx)
      end

      private def self.instance_fields_and_values(query_hash : Hash)
        values = query_hash.values.map { |x| x.is_a?(JSON::Any) ? x.to_json : x.as(DbValue) }
        {fields: query_hash.keys, values: values}
      end

      private def self.position_args(query_string : String)
        query_string
      end
    end
  end
end
