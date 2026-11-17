use hbb_common::{config::Config, ResultType};
use serde_derive::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    fs::{File, OpenOptions},
    io::{BufRead, BufReader, Write},
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(Debug, Deserialize, Serialize)]
struct Entry {
    id: String,
    connected_at: u64,
}

pub fn record(id: &str) -> ResultType<()> {
    let entry = Entry {
        id: id.to_owned(),
        connected_at: SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis() as u64,
    };
    let path = Config::path("remote-history.jsonl");
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let mut bytes = serde_json::to_vec(&entry)?;
    bytes.push(b'\n');
    // Sessions can run in separate processes, so never rewrite the history file.
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)?
        .write_all(&bytes)?;
    Ok(())
}

pub fn load() -> ResultType<HashMap<String, Vec<u64>>> {
    let file = match File::open(Config::path("remote-history.jsonl")) {
        Ok(file) => file,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(HashMap::new()),
        Err(err) => return Err(err.into()),
    };
    read_entries(BufReader::new(file))
}

fn read_entries(reader: impl BufRead) -> ResultType<HashMap<String, Vec<u64>>> {
    let mut history: HashMap<String, Vec<u64>> = HashMap::new();
    for line in reader.lines() {
        let entry: Entry = serde_json::from_str(&line?)?;
        history
            .entry(entry.id)
            .or_default()
            .push(entry.connected_at);
    }
    for times in history.values_mut() {
        times.sort_unstable_by(|a, b| b.cmp(a));
    }
    Ok(history)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn retains_every_connection_per_peer_newest_first() {
        let history = read_entries(std::io::Cursor::new(concat!(
            "{\"id\":\"172.29.0.52\",\"connected_at\":1000}\n",
            "{\"id\":\"other\",\"connected_at\":2000}\n",
            "{\"id\":\"172.29.0.52\",\"connected_at\":3000}\n",
            "{\"id\":\"172.29.0.52\",\"connected_at\":3000}\n",
        )))
        .unwrap();
        assert_eq!(history["172.29.0.52"], vec![3000, 3000, 1000]);
        assert_eq!(history["other"], vec![2000]);
    }

    #[test]
    fn reports_unreadable_history() {
        assert!(read_entries(std::io::Cursor::new("invalid\n")).is_err());
    }
}
