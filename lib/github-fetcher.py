#!/usr/bin/python
#
# Implements a simple github fetcher to facilitate the
# fetching of portions of a git repository. Using git
# is still recommended when fetching an entire repo
# but this comes in handy when only part of a repo
# is required.
#
# Copyright Wind River Ltd. 2017
#
import os
import json
import urllib
from urllib2 import urlopen
from optparse import OptionParser

BASE_URL = "https://api.github.com"

class Fetcher:
    repo_owner = ""
    repo = ""
    recursive = False
    branch = "master"
    repo_data = None

    def __init__(self, repo_owner, repo, options):
        self.repo_owner = repo_owner
        self.repo = repo
        if options.recursive:
            self.recursive = True
        if options.branch:
            self.branch = options.branch


    def get_metadata(self):
        """ Fetches the metadata of the repo.         """
        """ Directory names, file names, sha sums.... """
        url = "%s/repos/%s/%s/git/trees/%s?recursive=1" % (BASE_URL, self.repo_owner, self.repo, self.branch)
        try:
            response = urlopen(url)
            self.repo_data = json.load(response)
        except:
            raise

    def path_exists(self, path):
        """ Check if the path exists in the repo """
        """ Returns True if so, False otherwise  """
        for item in self.repo_data["tree"]:
            if item["path"] == path:
                return True
        return False

    def path_metadata(self, path):
        """ Check if the path exists in the repo and """
        """ returns the JSON metadata for the path.  """
        """ Returns None if path doesn't exist.      """
        for item in self.repo_data["tree"]:
            if item["path"] == path:
                return item
        return None

    def get(self, path, local_path):
        """ Fetch the item at the given path        """
        """ if it exists. Can be called recursively """
        metadata = self.path_metadata(path)
        if not metadata:
            raise IOError("path does not exist in repo")

        name = "%s/%s" % (local_path, metadata["path"].split('/')[-1])
        if metadata["type"] == "blob":
            try:
                response = urlopen(metadata["url"])
                data = json.load(response)
                with open(name, 'wb') as outfile:
                    outfile.write(data["content"].decode(data["encoding"]))
            except:
                raise

        if metadata["type"] == "tree":
            # Only get the directory information and write to file
            # if we are not recursive, otherwise get the dir contents
            if not self.recursive:
                 try:
                     response = urlopen(metadata["url"])
                     data = json.load(response)
                     with open(name, 'w') as outfile:
                         json.dump(data, outfile, indent=4)
                 except:
                     raise
            else:
                try:
                    if not os.path.exists(name):
                        os.makedirs(name)
                    for item in self.repo_data["tree"]:
                        item_path = item["path"]
                        if os.path.dirname(item_path) == path:
                            self.get(item_path, name)
                except:
                    raise


"""
main() when called as a script
"""
if __name__ == "__main__":
    parser = OptionParser()
    parser.usage = "%prog [options] repo_owner repo path"
    parser.add_option("-r", "--recursive", dest="recursive", action="store_true",
                      help="If path is a directory, fetch everything recursively from the directory.")
    parser.add_option("-b", "--branch", dest="branch",
                      help="Fetch from the HEAD of the specified branch. (default:master)")
    (options, args) =  parser.parse_args()

    if len(args) != 4:
        print("Missing required repo_owner, repo, path and local_path.")
        parser.print_help()
        exit(1)
    (repo_owner, repo, path, local_path) = args

    if not os.path.exists(local_path):
        print("Local path '%s' doesn't exist" % local_path)
        exit(2)

    if os.path.exists(local_path + '/' + path):
        print("Local file '%s' already exists. Aborting." % (local_path + '/' + path))
        exit(3)

    fetcher = Fetcher(repo_owner, repo, options)
    try:
        fetcher.get_metadata()
        fetcher.get(path, local_path)
    except IOError as e:
        print("Failed: %s" % e)
