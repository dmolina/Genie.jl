module Database

using Lazy
using Memoize
using PostgreSQL
using YAML
using Jinnie

const POSTGRESQL_ADAPTER = PostgreSQL

function parse_connection_data()
  YAML.load(open(abspath("config/database.yml")))
end

function env_connection_data()
  db_conn_data = parse_connection_data()

  if ( haskey(db_conn_data, Jinnie.config.app_env) ) 
    env_db_conn_data = db_conn_data[Jinnie.config.app_env]
    if ( haskey(env_db_conn_data, "adapter") )
      return Nullable(env_db_conn_data)
    end
  end
end

function db_connect(skip_db = false)
  env_db_conn_data = env_connection_data()
  if ( isnull(env_db_conn_data) ) return nothing end

  env_db_conn_data = Base.get(env_db_conn_data)
  if ( haskey(env_db_conn_data, "adapter") )
    @switch _ begin # don't know why but in here it throws a string in boolean context error -- works fine in REPL
      env_db_conn_data["adapter"] == "Postgres"; return connect(Postgres, 
                                                        env_db_conn_data["host"] == nothing ? "localhost" : env_db_conn_data["host"], 
                                                        env_db_conn_data["username"], 
                                                        env_db_conn_data["password"] == nothing ? "" : env_db_conn_data["password"], 
                                                        env_db_conn_data["database"] == nothing || skip_db ? "" : env_db_conn_data["database"], 
                                                        env_db_conn_data["port"] == nothing ? 5432 : env_db_conn_data["port"])
      error("Not implemented")
    end
  end
end

@memoize function conn_data()
  return Base.get(env_connection_data())
end

@memoize function query_tools(skip_db = false)
  adapter = db_adapter(conn_data()["adapter"])
  conn = db_connect(skip_db)

  return conn, adapter
end

function create_database()
  query("CREATE DATABASE $(conn_data()["database"])", skip_db = true, disconnect = true)
  Jinnie.log("Created database $(conn_data()["database"]) or database already exists")
end

function db_adapter(adapter_name)
  if adapter_name == "Postgres" 
    return eval(parse("PostgreSQL"))
  end
end

function create_migrations_table()
  sql = @switch _ begin 
    conn_data()["adapter"] == "Postgres"; "CREATE TABLE $(Jinnie.config.db_migrations_table_name) (version varchar(30) CONSTRAINT firstkey PRIMARY KEY)"
    error("Not implemented")
  end
  query(sql)
  Jinnie.log("Created table $(Jinnie.config.db_migrations_table_name) or table already exists")
end

function query(sql; skip_db = false, disconnect = false, system_query = false)
  conn, adapter = query_tools(skip_db)

  stmt = adapter.prepare(conn, sql)

  if ! system_query Jinnie.log("SQL QUERY: $sql") end

  @run_with_time result = adapter.execute(stmt)
  adapter.finish(stmt)

  if (disconnect) adapter.disconnect(conn) end

  return result
end

function escape_column_name(str, q = "\"")
  return  if startswith(str, "(") && endswith(str, ")") # expression let it through
            str
          elseif startswith(str, "\"") && endswith(str, "\"") 
            str
          else "$q$str$q"
          end
end

function escape_value(str, q = "'")
  if startswith(str, q) && endswith(str, q) 
      str
  else 
    q * replace(str, q, "$q$q") * q
  end
end

end